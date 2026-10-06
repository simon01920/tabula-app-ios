import Foundation
import Testing
@testable import TimetableCore

@Suite("ShareLink and ShareConfiguration")
struct ShareLinkTests {
    static let code = ShortCode("7KX2M9QH")!

    @Test func buildsLinksForTheConfiguredDomain() throws {
        #expect(ShareConfiguration.defaultDomain == "tabula.simondev.sk")
        #expect(ShareLink.shortCode(Self.code).urlString() == "https://tabula.simondev.sk/c/7KX2M9QH")
        #expect(ShareLink.inline(envelope: "1.abc-_").urlString() == "https://tabula.simondev.sk/t#1.abc-_")
        let custom = try #require(ShareConfiguration(domain: "Share.Example.ORG"))
        #expect(custom.domain == "share.example.org")
        #expect(ShareLink.shortCode(Self.code).urlString(configuration: custom) == "https://share.example.org/c/7KX2M9QH")
        #expect(ShareLink.shortCode(Self.code).url()?.absoluteString == "https://tabula.simondev.sk/c/7KX2M9QH")
    }

    @Test func endToEndInlineLink() throws {
        let envelope = try ShareExport.encode(from: ShareFixture.secondary(), timetableID: ShareFixture.secondaryTimetableID,
                                              includeTasks: true).envelope
        let link = ShareLink.inline(envelope: envelope.text)
        let url = try #require(link.url())
        #expect(url.fragment == envelope.text)
        let parsed = try ShareLink.parse(url.absoluteString)
        #expect(parsed == link)
        guard case .inline(let text) = parsed else { Issue.record("expected inline"); return }
        #expect(try ShareImport.preview(text).timetableName == "3.A Gymnázium")
    }

    @Test(arguments: [
        "https://tabula.simondev.sk/c/7KX2M9QH",
        "HTTPS://TABULA.SIMONDEV.SK/c/7KX2M9QH",
        "  https://tabula.simondev.sk/c/7KX2M9QH\n",
        "https://tabula.simondev.sk/c/7KX2M9QH?utm_source=chat&fbclid=x",
    ])
    func parsesShortCodeLinks(_ text: String) throws {
        #expect(try ShareLink.parse(text) == .shortCode(Self.code))
    }

    @Test func parsesInlineLinks() throws {
        #expect(try ShareLink.parse("https://tabula.simondev.sk/t#1.q1ZK") == .inline(envelope: "1.q1ZK"))
        #expect(try ShareLink.parse("https://tabula.simondev.sk/t?ref=qr#2.AAAA") == .inline(envelope: "2.AAAA"))
        let custom = try #require(ShareConfiguration(domain: "example.org"))
        #expect(try ShareLink.parse("https://example.org/c/7KX2M9QH", configuration: custom) == .shortCode(Self.code))
        #expect(throws: ShareError.invalidLink) { try ShareLink.parse("https://tabula.simondev.sk/c/7KX2M9QH", configuration: custom) }
    }

    @Test(arguments: [
        "", "   ", "https://", "https:///c/7KX2M9QH", "tabula.simondev.sk/c/7KX2M9QH",
        "http://tabula.simondev.sk/c/7KX2M9QH", "ftp://tabula.simondev.sk/c/7KX2M9QH", "javascript:alert(1)",
        "tabula://c/7KX2M9QH", "https:/tabula.simondev.sk/c/7KX2M9QH", "https//tabula.simondev.sk/c/7KX2M9QH",
        "https://evil.com/c/7KX2M9QH", "https://tabula.simondev.sk.evil.com/c/7KX2M9QH", "https://eviltabula.simondev.sk/c/7KX2M9QH",
        "https://evil.com#tabula.simondev.sk/c/7KX2M9QH", "https://evil.com/https://tabula.simondev.sk/c/7KX2M9QH",
        "https://tabula.simondev.sk@evil.com/c/7KX2M9QH", "https://evil.com@tabula.simondev.sk/c/7KX2M9QH",
        "https://user:pass@tabula.simondev.sk/c/7KX2M9QH", "https://tabula.simondev.sk:443/c/7KX2M9QH",
        "https://tabula.simondev.sk./c/7KX2M9QH", "https://tabula.simondev.sk\\@evil.com/c/7KX2M9QH",
        "https://tabulа.simondev.sk/c/7KX2M9QH", // Cyrillic "а"
        "https://tabula%2Esimondev.sk/c/7KX2M9QH", "https://[::1]/c/7KX2M9QH",
        "https://tabula.simondev.sk/c/7kx2m9qh", "https://tabula.simondev.sk/c/7KX2-M9QH", "https://tabula.simondev.sk/c/7KX2M9Q",
        "https://tabula.simondev.sk/c/7KX2M9QHX", "https://tabula.simondev.sk/c/7KX2M9QH/", "https://tabula.simondev.sk/c/7KX2M9QH/x",
        "https://tabula.simondev.sk/c/7KX2M9QH#frag", "https://tabula.simondev.sk/C/7KX2M9QH", "https://tabula.simondev.sk//c/7KX2M9QH",
        "https://tabula.simondev.sk/c/../t#1.AAAA", "https://tabula.simondev.sk/c/%37KX2M9QH", "https://tabula.simondev.sk/c/",
        "https://tabula.simondev.sk/t", "https://tabula.simondev.sk/t#", "https://tabula.simondev.sk/t/#1.AAAA",
        "https://tabula.simondev.sk/T#1.AAAA", "https://tabula.simondev.sk/t#1.AA%41A", "https://tabula.simondev.sk/t#1.AA AA",
        "https://tabula.simondev.sk/t#1.AAAA#x", "https://tabula.simondev.sk/t#1.AA=", "https://tabula.simondev.sk/t#1.AA\u{0}",
        "https://tabula.simondev.sk/t#1.AAÄA", "https://tabula.simondev.sk/x#1.AAAA", "https://tabula.simondev.sk",
        "https://tabula.simondev.sk/", "https://tabula.simondev.sk/c/7KX2M9QH\u{202E}", "https://tabula.simondev.sk/c/7KX2\u{200B}M9QH",
    ])
    func rejectsHostileLinks(_ text: String) {
        #expect(throws: ShareError.invalidLink) { try ShareLink.parse(text) }
    }

    @Test func rejectsOverlongLinks() throws {
        let body = String(repeating: "A", count: ShareLimits.maxLinkBytes)
        #expect(throws: ShareError.invalidLink) { try ShareLink.parse("https://tabula.simondev.sk/t#1." + body) }
        let whitespace = String(repeating: " ", count: 3 * ShareLimits.maxLinkBytes)
        #expect(throws: ShareError.invalidLink) { try ShareLink.parse(whitespace + "https://tabula.simondev.sk/c/7KX2M9QH") }
        // The largest envelope the codec produces still parses.
        let maximal = "1." + String(repeating: "A", count: ShareLimits.maxEnvelopeBytes - 2)
        #expect(try ShareLink.parse("https://tabula.simondev.sk/t#" + maximal) == .inline(envelope: maximal))
    }

    @Test(arguments: ["", "localhost", "tabula", "-tabula.sk", "tabula-.sk", "tab ula.sk", "tabula.sk/", "https://tabula.sk",
                      "tabula.sk:443", "tabula.sk.", ".tabula.sk", "tabula..sk", "user@tabula.sk", "tabulá.sk",
                      String(repeating: "a", count: 64) + ".sk", String(repeating: "abcdefghi.", count: 26) + "sk"])
    func rejectsInvalidDomains(_ domain: String) {
        #expect(ShareConfiguration(domain: domain) == nil)
    }

    @Test func fuzzedLinksNeverCrash() {
        var rng = TestRNG(seed: 0x11AA)
        let base = Array("https://tabula.simondev.sk/c/7KX2M9QH".utf8) + Array("?q=1#x".utf8)
        let pool = Array("htps:/#?.@%-_ABCXYZ0123456789tabula.simondev.sk\\ \t\u{7F}".utf8)
        var accepted = 0
        for _ in 0..<2000 {
            var bytes = base
            for _ in 0..<(1 + Int(rng.next() % 4)) {
                let index = Int(rng.next() % UInt64(bytes.count))
                switch rng.next() % 3 {
                case 0: bytes[index] = pool[Int(rng.next() % UInt64(pool.count))]
                case 1: bytes.remove(at: index)
                default: bytes.insert(pool[Int(rng.next() % UInt64(pool.count))], at: index)
                }
                if bytes.isEmpty { bytes = base }
            }
            if let link = try? ShareLink.parse(String(decoding: bytes, as: UTF8.self)) {
                accepted += 1
                // Whatever is accepted is one of the two shapes on the configured host.
                let text = link.urlString()
                #expect(text.hasPrefix("https://tabula.simondev.sk/c/") || text.hasPrefix("https://tabula.simondev.sk/t#"))
            }
        }
        #expect(accepted < 2000)
    }
}
