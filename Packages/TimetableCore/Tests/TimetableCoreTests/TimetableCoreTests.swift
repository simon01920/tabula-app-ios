import Testing
@testable import TimetableCore

@Suite("Phase 0 placeholder")
struct TimetableCorePlaceholderTests {
    @Test func schemaVersionIsOne() {
        #expect(TimetableCoreInfo.schemaVersion == 1)
    }
}

@Suite("AppGroup resolution (xtool bundle-ID prefix)")
struct AppGroupTests {
    @Test func canonicalBundleIDKeepsCanonicalGroup() {
        #expect(AppGroup.identifier(forBundleIdentifier: "sk.simondev.tabula") == "group.sk.simondev.tabula")
        #expect(AppGroup.identifier(forBundleIdentifier: "sk.simondev.tabula.TabulaWidgets") == "group.sk.simondev.tabula")
    }

    @Test func nilBundleIDFallsBackToCanonical() {
        #expect(AppGroup.identifier(forBundleIdentifier: nil) == AppGroup.canonicalIdentifier)
    }

    @Test func xtoolPrefixedAppAndWidgetResolveToSameGroup() {
        let app = AppGroup.identifier(forBundleIdentifier: "XTL-ABCD1234.sk.simondev.tabula")
        let widget = AppGroup.identifier(forBundleIdentifier: "XTL-ABCD1234.sk.simondev.tabula.TabulaWidgets")
        #expect(app == "group.XTL-ABCD1234.sk.simondev.tabula")
        #expect(widget == app)
    }

    @Test func detectsXtoolSigning() {
        #expect(AppGroup.isXtoolSigned(bundleIdentifier: "XTL-ABCD1234.sk.simondev.tabula"))
        #expect(!AppGroup.isXtoolSigned(bundleIdentifier: "sk.simondev.tabula"))
        #expect(!AppGroup.isXtoolSigned(bundleIdentifier: nil))
    }

    @Test func malformedPrefixWithoutDotFallsBack() {
        #expect(AppGroup.identifier(forBundleIdentifier: "XTL-NODOT") == AppGroup.canonicalIdentifier)
    }

    @Test func emptyBundleIDFallsBackToCanonical() {
        #expect(AppGroup.identifier(forBundleIdentifier: "") == AppGroup.canonicalIdentifier)
        #expect(!AppGroup.isXtoolSigned(bundleIdentifier: ""))
    }

    @Test func emptyXtoolIdentitySegmentFallsBackToCanonical() {
        #expect(AppGroup.identifier(forBundleIdentifier: "XTL-.sk.simondev.tabula") == AppGroup.canonicalIdentifier)
    }

    @Test func anyPrefixedExtensionMapsToTheSameGroupAsItsApp() {
        let app = AppGroup.identifier(forBundleIdentifier: "XTL-9F3A2B1C.sk.simondev.tabula")
        for ext in ["XTL-9F3A2B1C.sk.simondev.tabula.TabulaWidgets",
                    "XTL-9F3A2B1C.sk.simondev.tabula.ShareExtension",
                    "XTL-9F3A2B1C.sk.simondev.tabula.watchkitapp"] {
            #expect(AppGroup.identifier(forBundleIdentifier: ext) == app)
        }
        #expect(app == "group.XTL-9F3A2B1C.sk.simondev.tabula")
    }
}
