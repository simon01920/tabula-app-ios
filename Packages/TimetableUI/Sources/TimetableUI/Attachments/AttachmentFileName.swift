// File-name, content-type and link rules for attachments (PHASE3_PLAN §0.7, stage B3). Pure Foundation, Linux-tested
// (AttachmentStoreTests). The stored layout is `<store directory>/Attachments/<attachment UUID>/<sanitized name>`,
// so the name must never contain a path separator or be `.`/`..`; `AttachmentRef.fileName` may arrive from another
// device through sync, so every name read back is re-checked with `isSafeStoredName(_:)` before it is joined to a path.
import Foundation

/// Sanitises user/system supplied file names into a single safe path component.
public enum AttachmentFileName {
    /// Maximum length of a stored name in UTF-8 bytes (APFS allows 255; leave headroom for the system).
    public static let maxUTF8Length = 120
    /// Longest extension kept (letters and digits only).
    public static let maxExtensionLength = 10
    /// Base name used when nothing usable is left.
    public static let fallbackBase = "attachment"

    /// A single safe path component derived from `raw`:
    /// - Unicode NFC (a name typed on another device compares equal);
    /// - only the last path component (`../../x` → `x`, `a\b` → `b`);
    /// - control, format (bidi override) and `/ \ : * ? " < > |` characters become `_`;
    /// - leading/trailing whitespace and dots removed (no hidden files, never `.` or `..`);
    /// - the extension (≤ 10 ASCII letters/digits) is kept; the base is shortened on character boundaries so the
    ///   whole name fits `maxUTF8Length` bytes;
    /// - empty → `attachment` (+ `fallbackExtension` when the raw name had none).
    public static func sanitize(_ raw: String, fallbackExtension: String? = nil) -> String {
        let normalized = raw.precomposedStringWithCanonicalMapping
        let lastComponent = normalized
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .last.map(String.init) ?? ""
        var cleaned = String(String.UnicodeScalarView(lastComponent.unicodeScalars.map(replacingUnsafe)))
        cleaned = cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))

        var base = cleaned
        var ext: String?
        if let dot = cleaned.lastIndex(of: ".") {
            let candidate = String(cleaned[cleaned.index(after: dot)...])
            if isValidExtension(candidate) {
                ext = candidate
                base = String(cleaned[..<dot]).trimmingCharacters(in: CharacterSet.whitespaces
                    .union(CharacterSet(charactersIn: ".")))
            }
        }
        if ext == nil, let fallback = fallbackExtension, isValidExtension(fallback) {
            ext = fallback
        }
        if base.isEmpty { base = fallbackBase }
        let suffix = ext.map { "." + $0 } ?? ""
        let budget = maxUTF8Length - suffix.utf8.count
        base = truncated(base, maxUTF8: budget)
        // Truncation can expose trailing spaces/dots again.
        base = base.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        if base.isEmpty { base = fallbackBase }
        return base + suffix
    }

    /// `true` when `name` is exactly what `sanitize` would produce for it (one safe component, within limits).
    public static func isSafeStoredName(_ name: String) -> Bool {
        !name.isEmpty && sanitize(name) == name
    }

    /// The kept extension of a sanitised name, lowercased (`"Board.JPG"` → `"jpg"`), or `nil`.
    public static func pathExtension(of name: String) -> String? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let candidate = String(name[name.index(after: dot)...])
        return isValidExtension(candidate) ? candidate.lowercased() : nil
    }

    static func isValidExtension(_ candidate: String) -> Bool {
        !candidate.isEmpty && candidate.count <= maxExtensionLength
            && candidate.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    }

    private static let forbidden = Set("/\\:*?\"<>|".unicodeScalars)
    /// ZERO WIDTH NON-JOINER / JOINER (emoji ZWJ sequences, Persian/Indic text).
    private static let keptFormatScalars: Set<UInt32> = [0x200C, 0x200D]

    private static func replacingUnsafe(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        if forbidden.contains(scalar) { return "_" }
        switch scalar.properties.generalCategory {
        case .format:
            // Keep the joiners and tag characters that emoji sequences need; replace bidi overrides, BOM etc.
            return keptFormatScalars.contains(scalar.value) || (0xE0020...0xE007F).contains(scalar.value) ? scalar : "_"
        case .control, .lineSeparator, .paragraphSeparator, .surrogate, .unassigned, .privateUse:
            return "_"
        default:
            return scalar
        }
    }

    private static func truncated(_ text: String, maxUTF8: Int) -> String {
        guard maxUTF8 > 0 else { return "" }
        guard text.utf8.count > maxUTF8 else { return text }
        var result = ""
        var used = 0
        for character in text {
            let size = String(character).utf8.count
            if used + size > maxUTF8 { break }
            result.append(character)
            used += size
        }
        return result
    }
}

/// Uniform type identifiers for common attachment extensions. The app prefers `UTType(filenameExtension:)`
/// (UniformTypeIdentifiers is Apple-only); this table is the Linux-testable fallback so a ref always has a type.
public enum AttachmentContentType {
    /// Generic data (`public.data`).
    public static let generic = "public.data"

    static let byExtension: [String: String] = [
        "jpg": "public.jpeg", "jpeg": "public.jpeg", "png": "public.png", "heic": "public.heic", "heif": "public.heif",
        "gif": "com.compuserve.gif", "tif": "public.tiff", "tiff": "public.tiff", "webp": "org.webmproject.webp",
        "pdf": "com.adobe.pdf", "txt": "public.plain-text", "rtf": "public.rtf", "csv": "public.comma-separated-values-text",
        "m4a": "com.apple.m4a-audio", "mp3": "public.mp3", "wav": "com.microsoft.waveform-audio",
        "mov": "com.apple.quicktime-movie", "mp4": "public.mpeg-4", "zip": "public.zip-archive",
        "doc": "com.microsoft.word.doc", "docx": "org.openxmlformats.wordprocessingml.document",
        "xls": "com.microsoft.excel.xls", "xlsx": "org.openxmlformats.spreadsheetml.sheet",
        "ppt": "com.microsoft.powerpoint.ppt", "pptx": "org.openxmlformats.presentationml.presentation",
        "pages": "com.apple.iwork.pages.sffpages", "numbers": "com.apple.iwork.numbers.sffnumbers",
        "key": "com.apple.iwork.keynote.sffkey", "ics": "com.apple.ical.ics", "md": "net.daringfireball.markdown",
    ]

    /// `provided` when it is a plausible UTI, else the type for the name's extension, else `public.data`.
    public static func resolve(provided: String?, fileName: String) -> String {
        if let provided = provided?.trimmingCharacters(in: .whitespacesAndNewlines), !provided.isEmpty,
           provided.count <= 200, !provided.contains(where: { $0.isWhitespace || $0 == "/" }) {
            return provided
        }
        return AttachmentFileName.pathExtension(of: fileName).flatMap { byExtension[$0] } ?? generic
    }
}

/// Link attachments: only http(s), validated, never opened without the user's confirmation.
public enum AttachmentLink {
    /// Longest accepted URL (characters).
    public static let maxLength = 2_048

    /// The normalised URL for `input`, or `nil` when it is not an acceptable web link.
    ///
    /// Rules: trimmed; no whitespace/control characters inside; a missing scheme becomes `https://` (only when the
    /// text has no other scheme, so `javascript:…`, `file:…`, `tel:…` stay rejected); the scheme must be `http` or
    /// `https`; a host is required; user info (`https://bank.com@evil.example`) is rejected because it disguises
    /// the real host in the confirmation dialog.
    public static func validated(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0)
                  || CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let candidate: String
        if trimmed.range(of: "://") != nil {
            candidate = trimmed
        } else if hasForeignScheme(trimmed) {
            return nil
        } else {
            candidate = "https://" + trimmed
        }
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty, !host.hasPrefix("."), !host.contains(" "),
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return url
    }

    /// The host of a stored link (`"https://www.example.com/a"` → `"www.example.com"`), or `nil`.
    public static func host(of urlString: String?) -> String? {
        guard let urlString, let host = URLComponents(string: urlString)?.host, !host.isEmpty else { return nil }
        return host
    }

    /// `true` when `text` starts with `<scheme>:` that is not followed by a port-like number (e.g. `mailto:x`).
    private static func hasForeignScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let prefix = text[..<colon]
        guard !prefix.isEmpty, prefix.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0)
            || "+-.".unicodeScalars.contains($0) }) else { return false }
        // "example.com:8080/x" is host:port, not a scheme.
        let rest = text[text.index(after: colon)...]
        let portDigits = rest.prefix { $0.isNumber }
        if !portDigits.isEmpty, rest.dropFirst(portDigits.count).first.map({ $0 == "/" }) ?? true,
           prefix.contains(".") || prefix.lowercased() == "localhost" {
            return false
        }
        return true
    }
}
