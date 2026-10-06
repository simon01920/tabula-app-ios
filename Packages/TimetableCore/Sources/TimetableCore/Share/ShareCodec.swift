import Foundation

/// How an encoded share travels.
public enum ShareRoute: String, Hashable, Sendable, CaseIterable {
    /// In the link itself (`https://<domain>/t#<envelope>`, QR code): compressed payload ≤
    /// `ShareLimits.inlineCompressedBytes`.
    case inline
    /// Uploaded to the share service; the link carries an 8-character `ShortCode` (`https://<domain>/c/<code>`).
    case shortCode
}

/// An encoded payload: the envelope string plus its sizes and route.
public struct ShareEnvelope: Hashable, Sendable {
    /// `"<envelope version>." + base64url(raw DEFLATE(canonical JSON))`, e.g. `"1.q1ZKz…"`.
    public var text: String
    /// Size of the canonical JSON.
    public var jsonByteCount: Int
    /// Size of the DEFLATE stream (decides the route).
    public var compressedByteCount: Int
    /// Inline link or short code.
    public var route: ShareRoute
}

/// The share pipeline (docs/specs/SHARE_FORMAT.md §2): payload ⇄ canonical JSON ⇄ raw DEFLATE ⇄ base64url,
/// prefixed with the envelope version.
///
/// Decoding treats its input as hostile: every stage has a size limit, every failure is a typed `ShareError`,
/// nothing is interpreted before validation succeeds.
public enum ShareCodec {
    /// The envelope format this app writes and reads: `"1."` = raw DEFLATE + base64url without padding.
    public static let envelopeVersion = 1

    // MARK: Encode

    /// Canonical JSON of a valid payload (sorted keys, canonical arrays, no whitespace). Validates first.
    public static func canonicalJSON(_ payload: SharePayloadV1) throws(ShareError) -> [UInt8] {
        _ = try payload.validate()
        let data: Data
        do {
            data = try TabulaJSON.makeEncoder().encode(payload)
        } catch {
            // Encoding plain value types cannot fail; surface it as a codec failure if it ever does.
            throw .compressionFailed
        }
        guard data.count <= ShareLimits.maxJSONBytes else { throw .decompressedTooLarge }
        return [UInt8](data)
    }

    /// Validates and encodes `payload`.
    ///
    /// - Throws: a validation error, `.decompressedTooLarge` (JSON over 1 MB), `.envelopeTooLarge` (envelope over
    ///   64 KB) or `.compressionFailed`.
    public static func encode(_ payload: SharePayloadV1) throws(ShareError) -> ShareEnvelope {
        let json = try canonicalJSON(payload)
        let compressed = try ShareDeflate.compress(json)
        let text = "\(envelopeVersion)." + Base64URL.encode(compressed)
        guard text.utf8.count <= ShareLimits.maxEnvelopeBytes else { throw .envelopeTooLarge(byteCount: text.utf8.count) }
        return ShareEnvelope(text: text, jsonByteCount: json.count, compressedByteCount: compressed.count,
                             route: compressed.count <= ShareLimits.inlineCompressedBytes ? .inline : .shortCode)
    }

    // MARK: Decode

    /// Decodes and validates an envelope string (from a link fragment, the share service, or pasted text).
    public static func decode(_ envelope: String) throws(ShareError) -> SharePayloadV1 {
        try decode(utf8: Array(envelope.utf8))
    }

    /// Decodes and validates envelope bytes.
    static func decode(utf8 bytes: [UInt8]) throws(ShareError) -> SharePayloadV1 {
        guard !bytes.isEmpty else { throw .malformedEnvelope }
        guard bytes.count <= ShareLimits.maxEnvelopeBytes else { throw .envelopeTooLarge(byteCount: bytes.count) }
        guard let dot = bytes.firstIndex(of: UInt8(ascii: ".")) else { throw .malformedEnvelope }
        let version = try envelopeVersion(of: bytes[..<dot])
        guard version == envelopeVersion else {
            throw version > envelopeVersion ? .newerVersion(version) : .unsupportedVersion
        }
        let body = bytes[(dot + 1)...]
        guard !body.isEmpty else { throw .malformedEnvelope }
        guard let compressed = Base64URL.decode(body) else { throw .invalidBase64 }
        let json = try ShareDeflate.decompress(compressed, maxOutput: ShareLimits.maxJSONBytes)
        return try decodeJSON(json)
    }

    /// Parses the envelope prefix: 1–3 ASCII digits without a leading zero (`"0"` itself parses and is then
    /// unsupported). Anything else is `.unsupportedVersion`.
    static func envelopeVersion(of prefix: ArraySlice<UInt8>) throws(ShareError) -> Int {
        guard (1...3).contains(prefix.count),
              prefix.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
              prefix.count == 1 || prefix.first != UInt8(ascii: "0") else { throw .unsupportedVersion }
        return prefix.reduce(0) { $0 * 10 + Int($1 - UInt8(ascii: "0")) }
    }

    /// Decodes and validates decompressed payload bytes: UTF-8, nesting depth, JSON shape, payload version,
    /// then `SharePayloadV1.validate()`.
    static func decodeJSON(_ json: [UInt8]) throws(ShareError) -> SharePayloadV1 {
        guard json.count <= ShareLimits.maxJSONBytes else { throw .decompressedTooLarge }
        guard isValidUTF8(json) else { throw .invalidUTF8 }
        guard nestingDepth(json, limit: ShareLimits.maxJSONDepth) <= ShareLimits.maxJSONDepth else {
            throw .malformedPayload(path: "")
        }
        let payload: SharePayloadV1
        do {
            payload = try TabulaJSON.makeDecoder().decode(SharePayloadV1.self, from: Data(json))
        } catch let error as ShareError {
            throw error
        } catch let error as DecodingError {
            throw .malformedPayload(path: path(of: error))
        } catch {
            throw .malformedPayload(path: "")
        }
        _ = try payload.validate()
        return payload
    }

    // MARK: Guards

    /// `true` when `bytes` is well-formed UTF-8 (no overlongs, surrogates or values above U+10FFFF).
    static func isValidUTF8(_ bytes: [UInt8]) -> Bool {
        var iterator = bytes.makeIterator()
        var decoder = UTF8()
        while true {
            switch decoder.decode(&iterator) {
            case .scalarValue: continue
            case .emptyInput: return true
            case .error: return false
            }
        }
    }

    /// The maximum nesting depth of JSON arrays/objects in `bytes`, scanning outside strings only. Stops early
    /// once `limit` is exceeded (returns `limit + 1`). Malformed JSON is left to the decoder.
    static func nestingDepth(_ bytes: [UInt8], limit: Int) -> Int {
        var depth = 0
        var maxDepth = 0
        var inString = false
        var escaped = false
        for byte in bytes {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "["), UInt8(ascii: "{"):
                depth += 1
                maxDepth = max(maxDepth, depth)
                if maxDepth > limit { return limit + 1 }
            case UInt8(ascii: "]"), UInt8(ascii: "}"):
                depth -= 1
            default:
                break
            }
        }
        return maxDepth
    }

    /// Wire path of a decoding error (diagnostics only).
    static func path(of error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context): return SharePath.string(context.codingPath + [key])
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            return SharePath.string(context.codingPath)
        @unknown default: return ""
        }
    }
}
