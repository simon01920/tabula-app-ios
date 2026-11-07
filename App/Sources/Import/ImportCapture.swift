// Photo import capture (Phase 9 I2, AI_IMPORT.md pipeline step 0): where the picture of the timetable comes from.
//   Scan Document   VisionKit `VNDocumentCameraViewController` (perspective-corrected pages); shown only when
//                   `isSupported`. The camera prompt uses NSCameraUsageDescription (InfoPlist.xcstrings, written for
//                   scanning a printed timetable or a QR code).
//   Choose Photo    `photosPicker` (out of process: no photo-library permission).
//   Choose File     `fileImporter` (images and PDF). PDF pages are rendered with PDFKit; a multi-page file asks for
//                   the page first (`ImportPDFPagePicker`).
// Every source ends as one `ImportImage`: upright, at most `ImportImageLoader.maxPixels` on the long side, so Vision
// gets a predictable size and the review screen shows exactly what was read.
// API names checked in iPhoneOS27.0.sdk (2026-11-02): VNDocumentCameraViewController (class var isSupported, delegate
//   documentCameraViewController(_:didFinishWith:), …DidCancel(_:), …(_:didFailWithError:)), VNDocumentCameraScan
//   (pageCount, imageOfPage(at:)); PDFDocument(data:), pageCount, page(at:), PDFPage.bounds(for:),
//   PDFPage.thumbnail(of:for:); UIGraphicsImageRenderer (thread-safe, iOS 10).
// Phase 10 WP3:
// - P9: a picked photo is decoded straight to at most `maxPixels` with `CGImageSourceCreateThumbnailAtIndex`
//   (`kCGImageSourceThumbnailMaxPixelSize`, orientation applied), as AttachmentRow does: `UIImage(data:)` + `draw(in:)`
//   decoded a 48 MP photo in full (≈ 190 MB) first.
// - P10: reading the picked file and inspecting a PDF run off the main actor (`@concurrent`).
// - U11: the page picker knows the page count up front (`PDFInspection`); it shows a spinner while the document opens,
//   a `ContentUnavailableView` when it cannot (damaged or locked), and renders each preview lazily as its cell appears
//   (`PDFPageThumbnailer`, one actor-isolated `PDFDocument`) instead of every page before showing any.
// APIs checked in Apple's documentation JSON (2026-11-05): CGImageSourceCreateWithData(_:_:) (iOS 4),
//   PDFDocument.isLocked (iOS 11).
import ImageIO
import PDFKit
import SwiftUI
import UIKit
import VisionKit

/// The picture the import reads: upright (`imageOrientation == .up`), scale 1, at most `maxPixels` on the long side.
struct ImportImage: Sendable {
    let image: UIImage

    var cgImage: CGImage? { image.cgImage }
    var pixelSize: CGSize { image.size }
}

enum ImportImageLoader {
    /// Long-side limit. Vision reads table text well at this size; larger photos only cost memory and time.
    static let maxPixels: CGFloat = 3000

    /// Redraws `image` upright at scale 1, downscaled to `maxPixels` (never upscaled).
    @concurrent
    static func normalise(_ image: UIImage) async -> ImportImage {
        let size = image.size
        let longSide = max(size.width, size.height)
        let factor = longSide > maxPixels ? maxPixels / longSide : 1
        let target = CGSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let upright = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return ImportImage(image: upright)
    }

    /// An image file's bytes (`nil` when they are not an image), decoded at most `maxPixels` on the long side
    /// (never the full-size bitmap), upright, then drawn on white.
    @concurrent
    static func image(from data: Data) async -> ImportImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return await normalise(UIImage(cgImage: decoded))
    }

    /// Renders one PDF page on white, `maxPixels` on its long side.
    @concurrent
    static func render(pdf data: Data, pageIndex: Int) async -> ImportImage? {
        guard let document = PDFDocument(data: data), let page = document.page(at: pageIndex) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let longSide = max(bounds.width, bounds.height)
        guard longSide > 0 else { return nil }
        let factor = maxPixels / longSide
        let image = page.thumbnail(of: CGSize(width: bounds.width * factor, height: bounds.height * factor), for: .mediaBox)
        return await normalise(image)
    }

    /// What a PDF holds, off the main actor.
    @concurrent
    static func inspect(pdf data: Data) async -> PDFInspection {
        guard let document = PDFDocument(data: data) else { return .unreadable }
        if document.isLocked { return .locked }
        return document.pageCount > 0 ? .pages(document.pageCount) : .unreadable
    }

    /// Reads a file the user picked in Files (security-scoped while reading), off the main actor.
    @concurrent
    static func readPicked(_ url: URL) async -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)   // QA: read fully while the security scope is open
    }
}

/// A picked PDF: not a PDF (or damaged), password-protected, or its page count.
enum PDFInspection: Equatable, Sendable {
    case unreadable
    case locked
    case pages(Int)
}

/// Page previews of one PDF, one at a time: the document is parsed once, on first use, and only touched inside the
/// actor (`PDFDocument` is not Sendable).
actor PDFPageThumbnailer {
    private let data: Data
    private var document: PDFDocument?
    private var opened = false

    init(data: Data) { self.data = data }

    /// Whether the document opens with pages (unlocked).
    func open() -> Bool {
        guard let document = load() else { return false }
        return !document.isLocked && document.pageCount > 0
    }

    /// A preview of page `index` that fits `side` × `side` points, or `nil` when the page is missing.
    func thumbnail(page index: Int, side: CGFloat) -> UIImage? {
        load()?.page(at: index)?.thumbnail(of: CGSize(width: side, height: side), for: .mediaBox)
    }

    private func load() -> PDFDocument? {
        if !opened {
            document = PDFDocument(data: data)
            opened = true
        }
        return document
    }
}

// MARK: - Document camera

/// VisionKit's document camera. `onScan` gets the first page (a timetable is one page); `onCancel` covers Cancel and
/// failures (a failure is reported with `failed: true`).
struct DocumentCameraView: UIViewControllerRepresentable {
    let onScan: @MainActor (UIImage) -> Void
    let onCancel: @MainActor (_ failed: Bool) -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    // The delegate is called on the main thread; `@preconcurrency` checks that at run time.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let onScan: @MainActor (UIImage) -> Void
        let onCancel: @MainActor (Bool) -> Void

        init(onScan: @escaping @MainActor (UIImage) -> Void, onCancel: @escaping @MainActor (Bool) -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let image = scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil
            if let image { onScan(image) } else { onCancel(false) }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel(false)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            onCancel(true)
        }
    }
}

// MARK: - PDF page picker

/// "Which page has the timetable?" for a multi-page PDF: a grid of page previews, each rendered when its cell
/// appears. States: opening (spinner), failed (`ContentUnavailableView` with "Choose Another File" → `onBack`),
/// ready (the grid; a page whose preview fails shows a page symbol and stays selectable).
struct ImportPDFPagePicker: View {
    let pageCount: Int
    let onPick: (Int) -> Void
    let onBack: () -> Void
    @Environment(AppModel.self) private var model
    @State private var thumbnailer: PDFPageThumbnailer
    @State private var readable: Bool?

    init(data: Data, pageCount: Int, onPick: @escaping (Int) -> Void, onBack: @escaping () -> Void) {
        self.pageCount = pageCount
        self.onPick = onPick
        self.onBack = onBack
        _thumbnailer = State(initialValue: PDFPageThumbnailer(data: data))
    }

    var body: some View {
        content
            .navigationTitle(Text("import.pdf.pages.title"))
            .navigationBarTitleDisplayMode(.inline)
            .task { readable = await thumbnailer.open() }
    }

    @ViewBuilder private var content: some View {
        switch readable {
        case nil:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case false?:
            ContentUnavailableView {
                Label { Text("import.pdf.pages.failed.title") } icon: { Image(systemName: "doc.questionmark") }
            } description: {
                Text("import.pdf.pages.failed.message")
            } actions: {
                Button(action: onBack) { Text("import.pdf.pages.failed.action").onInkLabel() }
                    .buttonStyle(.borderedProminent)
            }
        case true?:
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Button { onPick(index) } label: {
                            VStack(spacing: 6) {
                                PDFPagePreview(thumbnailer: thumbnailer, index: index)
                                Text(verbatim: pageLabel(index))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: pageLabel(index)))
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(16)
            }
        }
    }

    private func pageLabel(_ index: Int) -> String {
        model.renderer.format(key: "import.pdf.page", arguments: [.integer(Int64(index + 1))])
    }
}

/// One page preview: a spinner until rendered, then the page, or a page symbol when the page cannot be drawn.
private struct PDFPagePreview: View {
    let thumbnailer: PDFPageThumbnailer
    let index: Int
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .background(Color.white)
            } else {
                ZStack {
                    Color.white
                    if failed {
                        Image(systemName: "doc").font(.largeTitle).foregroundStyle(Color.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 140, height: 190)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator)
        }
        .task {
            let rendered = await thumbnailer.thumbnail(page: index, side: 400)
            guard !Task.isCancelled else { return }
            image = rendered
            failed = rendered == nil
        }
    }
}
