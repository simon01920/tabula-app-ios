import Foundation

/// Where share links point. The domain is configuration, not code: the real domain does not exist yet.
public struct ShareConfiguration: Hashable, Sendable {
    /// Placeholder domain until the share service is deployed (docs/specs/SHARING.md).
    public static let defaultDomain = "tabula.simondev.sk"
    /// Configuration with `defaultDomain`.
    public static let `default` = ShareConfiguration(checkedDomain: defaultDomain)

    /// Lowercase ASCII host name (IDNs must be given in punycode).
    public let domain: String

    /// Creates a configuration, or `nil` unless `domain` is a plain DNS host name: 2+ labels of `a–z 0–9 -`
    /// (1–63 characters, no leading/trailing `-`), at most 253 characters, no scheme, port, path or trailing dot.
    /// ASCII letters are lowercased.
    public init?(domain: String) {
        let lowered = String(decoding: domain.utf8.map(ShareLink.asciiLowercased), as: UTF8.self)
        guard Self.isValidHost(lowered) else { return nil }
        self.domain = lowered
    }

    private init(checkedDomain: String) {
        domain = checkedDomain
    }

    static func isValidHost(_ host: String) -> Bool {
        let bytes = Array(host.utf8)
        guard (1...253).contains(bytes.count) else { return false }
        let labels = bytes.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            guard (1...63).contains(label.count), label.first != UInt8(ascii: "-"), label.last != UInt8(ascii: "-") else {
                return false
            }
            return label.allSatisfy { byte in
                (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                    || byte == UInt8(ascii: "-")
            }
        }
    }
}

/// A share link: `https://<domain>/t#<envelope>` (inline, the fragment never reaches a server) or
/// `https://<domain>/c/<code>` (short code). docs/specs/SHARE_FORMAT.md §8.
public enum ShareLink: Hashable, Sendable {
    /// The payload travels in the fragment. `envelope` is only syntax-checked by `parse`; decode it with
    /// `ShareCodec.decode(_:)`.
    case inline(envelope: String)
    /// The payload is stored by the share service under `code`.
    case shortCode(ShortCode)

    /// The link for `configuration`'s domain.
    public func urlString(configuration: ShareConfiguration = .default) -> String {
        switch self {
        case .inline(let envelope): return "https://\(configuration.domain)/t#\(envelope)"
        case .shortCode(let code): return "https://\(configuration.domain)/c/\(code.rawValue)"
        }
    }

    /// The link as a `URL`.
    public func url(configuration: ShareConfiguration = .default) -> URL? {
        URL(string: urlString(configuration: configuration))
    }

    /// Strictly parses an (untrusted) link.
    ///
    /// Accepted: optional surrounding whitespace; scheme `https` (any case); host equal to the configured domain
    /// (any case; no user info, port or trailing dot); then exactly `/t#<envelope>` with a non-empty fragment
    /// of `A–Z a–z 0–9 . _ -`, or exactly `/c/<CODE>` with a canonical code and no fragment. A query string
    /// (e.g. tracking parameters added by messengers) is ignored. Everything else — other schemes or hosts,
    /// extra path segments, percent-encoding, non-ASCII characters, inner whitespace, links longer than
    /// `ShareLimits.maxLinkBytes` — is `.invalidLink`. Nothing in the link is interpreted beyond this shape.
    public static func parse(_ text: String, configuration: ShareConfiguration = .default) throws(ShareError) -> ShareLink {
        // Bound the work before looking at the text (whitespace around a maximal link is still accepted).
        guard text.utf8.count <= 2 * ShareLimits.maxLinkBytes else { throw .invalidLink }
        var scalars = Array(text.unicodeScalars.drop(while: { $0.properties.isWhitespace }))
        while let last = scalars.last, last.properties.isWhitespace { scalars.removeLast() }
        guard scalars.count <= ShareLimits.maxLinkBytes,
              scalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else { throw .invalidLink }
        let bytes = scalars.map { UInt8($0.value) }

        let scheme = Array("https://".utf8)
        guard bytes.count > scheme.count, bytes.prefix(scheme.count).map(asciiLowercased) == scheme else {
            throw .invalidLink
        }
        let rest = bytes.dropFirst(scheme.count)
        let authorityEnd = rest.firstIndex { $0 == UInt8(ascii: "/") || $0 == UInt8(ascii: "?") || $0 == UInt8(ascii: "#") }
            ?? rest.endIndex
        guard rest[rest.startIndex..<authorityEnd].map(asciiLowercased) == Array(configuration.domain.utf8) else {
            throw .invalidLink
        }
        let afterAuthority = rest[authorityEnd...]
        let fragmentStart = afterAuthority.firstIndex(of: UInt8(ascii: "#"))
        let beforeFragment = afterAuthority[..<(fragmentStart ?? afterAuthority.endIndex)]
        let pathEnd = beforeFragment.firstIndex(of: UInt8(ascii: "?")) ?? beforeFragment.endIndex
        let path = Array(beforeFragment[..<pathEnd])
        let fragment = fragmentStart.map { afterAuthority[($0 + 1)...] }

        if path == Array("/t".utf8) {
            guard let fragment, !fragment.isEmpty, fragment.allSatisfy(isEnvelopeByte) else { throw .invalidLink }
            return .inline(envelope: String(decoding: fragment, as: UTF8.self))
        }
        let codePrefix = Array("/c/".utf8)
        if path.starts(with: codePrefix), fragment == nil,
           let code = ShortCode(String(decoding: path.dropFirst(codePrefix.count), as: UTF8.self)) {
            return .shortCode(code)
        }
        throw .invalidLink
    }

    static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }

    private static func isEnvelopeByte(_ byte: UInt8) -> Bool {
        Base64URL.value(of: byte) != nil || byte == UInt8(ascii: ".")
    }
}
