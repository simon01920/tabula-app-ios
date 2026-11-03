// DEBUG fixtures of the photo import (Phase 9 I2): I1's Slovak aSc fixture with OCR noise
// (`Packages/TimetableCore/Tests/Fixtures/import/sk-asc-human-noisy.json`, its `table`, copied verbatim: Po–Pi rows,
// periods 1–13 with start times, multi-period spans, 'St' for 'Št', 'lS1', 'H4PI', low-confidence cells) and a picture
// drawn from the same cell boxes, so the review's highlights line up with it. Used by the `import.*` screenshot routes
// and the capture screen's "Use Sample Picture (Debug)" (the real Vision → parser pipeline on this picture, on device).
// Re-copy the JSON when I1 changes the fixture.
#if DEBUG
import SwiftUI
import TimetableCore
import TimetableUI

enum ImportFixtures {
    /// The picture's size in pixels (landscape, like a screenshot of the aSc export).
    static let page = CGSize(width: 2400, height: 1150)

    /// `sk-asc-human-noisy.json` › `table`.
    static let ascNoisyJSON = #"""
    {"version":1,"pageWidth":2480,"pageHeight":3508,"languages":["sk"],"cells":[{"text":"1\n7.00","row":0,"column":1,"box":{"x":0.1,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"2\n7.50","row":0,"column":2,"box":{"x":0.1677,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"3\n8.40","row":0,"column":3,"box":{"x":0.2354,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"4\n9.30","row":0,"column":4,"box":{"x":0.3031,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"5\n10.20","row":0,"column":5,"box":{"x":0.3708,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"6\n11.10","row":0,"column":6,"box":{"x":0.4385,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"7\n12.00","row":0,"column":7,"box":{"x":0.5062,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"8\n12.50","row":0,"column":8,"box":{"x":0.5738,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"9\n13.50","row":0,"column":9,"box":{"x":0.6415,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"10\n14.40","row":0,"column":10,"box":{"x":0.7092,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"11\n15.30","row":0,"column":11,"box":{"x":0.7769,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"12\n16.20","row":0,"column":12,"box":{"x":0.8446,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"13\n17.10","row":0,"column":13,"box":{"x":0.9123,"y":0.05,"width":0.0677,"height":0.15},"confidence":0.97},{"text":"Po","row":1,"column":0,"box":{"x":0.02,"y":0.2,"width":0.08,"height":0.15},"confidence":0.97},{"text":"prax\naaa","row":1,"column":2,"columnSpan":6,"box":{"x":0.1677,"y":0.2,"width":0.4062,"height":0.15},"confidence":0.95},{"text":"Ut","row":2,"column":0,"box":{"x":0.02,"y":0.35,"width":0.08,"height":0.15},"confidence":0.97},{"text":"SPAJ\n3P1","row":2,"column":1,"box":{"x":0.1,"y":0.35,"width":0.0677,"height":0.15},"confidence":0.95},{"text":"SAL\n3S1","row":2,"column":3,"columnSpan":2,"box":{"x":0.2354,"y":0.35,"width":0.1354,"height":0.15},"confidence":0.95},{"text":"SPAJ\nAula","row":2,"column":5,"box":{"x":0.3708,"y":0.35,"width":0.0677,"height":0.15},"confidence":0.95},{"text":"TPVAJ1\nAula","row":2,"column":8,"columnSpan":2,"box":{"x":0.5738,"y":0.35,"width":0.1354,"height":0.15},"confidence":0.95},{"text":"TPVAJ1\n3S1","row":2,"column":10,"box":{"x":0.7092,"y":0.35,"width":0.0677,"height":0.15},"confidence":0.95},{"text":"St","row":3,"column":0,"box":{"x":0.02,"y":0.5,"width":0.08,"height":0.15},"confidence":0.97},{"text":"MPV\nlS1","row":3,"column":1,"box":{"x":0.1,"y":0.5,"width":0.0677,"height":0.15},"confidence":0.41},{"text":"ZaExk\n3P1","row":3,"column":3,"box":{"x":0.2354,"y":0.5,"width":0.0677,"height":0.15},"confidence":0.95},{"text":"Muzejna pedagogika\nH5S1","row":3,"column":8,"columnSpan":2,"box":{"x":0.5738,"y":0.5,"width":0.1354,"height":0.15},"confidence":0.55},{"text":"St","row":4,"column":0,"box":{"x":0.02,"y":0.65,"width":0.08,"height":0.15},"confidence":0.97},{"text":"Teor. a prax vyuc. hist. I\nH4PI","row":4,"column":3,"columnSpan":3,"box":{"x":0.2354,"y":0.65,"width":0.2031,"height":0.15},"confidence":0.48},{"text":"Reg. dej. vo vyuč. dej. str.\nH4P1","row":4,"column":6,"columnSpan":2,"box":{"x":0.4385,"y":0.65,"width":0.1354,"height":0.15},"confidence":0.95},{"text":"Pi","row":5,"column":0,"box":{"x":0.02,"y":0.8,"width":0.08,"height":0.15},"confidence":0.97},{"text":"MPV\nAula","row":5,"column":9,"box":{"x":0.6415,"y":0.8,"width":0.0677,"height":0.15},"confidence":0.95},{"text":"SAL\nAula","row":5,"column":12,"box":{"x":0.8446,"y":0.8,"width":0.0677,"height":0.15},"confidence":0.95}]}
    """#

    /// Subjects the user already has: "MPV" and "SAL" are their initials, so the review asks (abbreviation questions).
    static let knownSubjects = ["Metodika primárneho vzdelávania", "Seminár anglickej literatúry"]

    /// What Vision would report for the picture (the fixture's boxes are page-normalised, so they fit `page` too).
    static let table: RecognizedTable = {
        var table = (try? JSONDecoder().decode(RecognizedTable.self, from: Data(ascNoisyJSON.utf8))) ?? RecognizedTable()
        table.pageWidth = page.width
        table.pageHeight = page.height
        return table
    }()

    /// The picture of the table (black on white, like a printed aSc export); rendered once.
    @MainActor static var image: UIImage {
        if let cachedImage { return cachedImage }
        let renderer = ImageRenderer(content: FixturePage(table: table).frame(width: page.width, height: page.height))
        renderer.scale = 1
        let image = renderer.uiImage ?? UIImage()
        cachedImage = image
        return image
    }

    @MainActor private static var cachedImage: UIImage?

    /// The parsed review (the real parser on the fixture table).
    static var review: ImportReview {
        ImportReview(candidate: TimetableImportParser.parse(table, options: ImportParserOptions(knownSubjects: knownSubjects)),
                     timetableName: "Rozvrh 2024/25")
    }

    @MainActor static func model(stage: PhotoImportModel.Stage, step: ImportStep = .reading,
                                 anchor: String? = nil) -> PhotoImportModel {
        let flow = PhotoImportModel(stage: stage, step: step, image: image, table: table,
                                    review: stage == .review ? review : nil)
        flow.initialAnchor = anchor
        return flow
    }
}

/// Capture screen row (DEBUG): runs the real Vision → parser pipeline on the fixture picture, on the device.
struct ImportSampleSection: View {
    let start: (UIImage) -> Void

    var body: some View {
        Section {
            Button { start(ImportFixtures.image) } label: {
                Label { Text(verbatim: "Use Sample Picture (Debug)") } icon: { Image(systemName: "ladybug") }
            }
        } footer: {
            Text(verbatim: "Developer check: the I1 aSc fixture drawn as a picture, through Vision, the parser and (if available) Apple Intelligence.")
        }
    }
}

/// The fixture page, drawn from the table's cell boxes: grid lines, the first line top-leading (wrapping), the
/// second line (room / time) bottom-trailing.
private struct FixturePage: View {
    let table: RecognizedTable

    var body: some View {
        Canvas { context, size in
            for cell in table.cells {
                guard let box = cell.box else { continue }
                let rect = CGRect(x: box.x * size.width, y: box.y * size.height,
                                  width: box.width * size.width, height: box.height * size.height)
                context.stroke(Path(rect), with: .color(.black), lineWidth: 2)
                let lines = cell.text.split(separator: "\n").map(String.init)
                guard let first = lines.first else { continue }
                let inset = rect.insetBy(dx: 10, dy: 8)
                context.draw(Text(verbatim: first).font(.system(size: 30, weight: .bold)).foregroundColor(.black),
                             in: CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height * 0.62))
                if lines.count > 1 {
                    context.draw(Text(verbatim: lines[1]).font(.system(size: 26)).foregroundColor(.black),
                                 at: CGPoint(x: inset.maxX, y: inset.maxY), anchor: .bottomTrailing)
                }
            }
        }
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
#endif // DEBUG
