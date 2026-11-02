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

    /// An image file's bytes (`nil` when they are not an image).
    @concurrent
    static func image(from data: Data) async -> ImportImage? {
        guard let image = UIImage(data: data) else { return nil }
        return await normalise(image)
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

    /// Small page previews for the page picker.
    @concurrent
    static func thumbnails(pdf data: Data, side: CGFloat) async -> [UIImage] {
        guard let document = PDFDocument(data: data) else { return [] }
        return (0..<document.pageCount).compactMap { index in
            document.page(at: index)?.thumbnail(of: CGSize(width: side, height: side), for: .mediaBox)
        }
    }

    /// Reads a file the user picked in Files (security-scoped while reading).
    static func readPicked(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
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

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: @MainActor (UIImage) -> Void
        let onCancel: @MainActor (Bool) -> Void

        init(onScan: @escaping @MainActor (UIImage) -> Void, onCancel: @escaping @MainActor (Bool) -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let image = scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil
            MainActor.assumeIsolated {
                if let image { onScan(image) } else { onCancel(false) }
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            MainActor.assumeIsolated { onCancel(false) }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            MainActor.assumeIsolated { onCancel(true) }
        }
    }
}

// MARK: - PDF page picker

/// "Which page has the timetable?" for a multi-page PDF: a grid of page previews.
struct ImportPDFPagePicker: View {
    let data: Data
    let onPick: (Int) -> Void
    @Environment(AppModel.self) private var model
    @State private var thumbnails: [UIImage] = []

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, thumbnail in
                    Button { onPick(index) } label: {
                        VStack(spacing: 6) {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator)
                                }
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
        .overlay { if thumbnails.isEmpty { ProgressView() } }
        .navigationTitle(Text("import.pdf.pages.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { thumbnails = await ImportImageLoader.thumbnails(pdf: data, side: 400) }
    }

    private func pageLabel(_ index: Int) -> String {
        model.renderer.format(key: "import.pdf.page", arguments: [.integer(Int64(index + 1))])
    }
}
