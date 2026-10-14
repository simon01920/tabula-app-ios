// One row of the task editor's attachments section (stage B3): thumbnail (downsampled with ImageIO, never the full
// image in memory) or an SF Symbol chosen by kind/UTI, title, details (size, link host, voice-note duration) and a
// play/pause control for voice notes.
// APIs: CGImageSourceCreateWithURL + CGImageSourceCreateThumbnailAtIndex with kCGImageSourceThumbnailMaxPixelSize /
//       kCGImageSourceCreateThumbnailFromImageAlways / kCGImageSourceCreateThumbnailWithTransform (iOS 4),
//       UTType(_:) + conforms(to:) (iOS 14), Int64.formatted(.byteCount(style:)), ScaledMetric.
//       Docs checked 2026-10-10 (docs/ENVIRONMENT.md §22).
import ImageIO
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit
import UniformTypeIdentifiers

struct AttachmentRow: View {
    let ref: AttachmentRef
    /// The stored file, or `nil` when it is not on this device (or the ref is a link).
    let fileURL: URL?
    let locale: Locale
    let player: VoiceNotePlayer
    let activate: () -> Void

    @State private var thumbnail: UIImage?
    @State private var duration: TimeInterval?
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 44
    @Environment(\.displayScale) private var displayScale

    private var isLink: Bool { ref.kind == .link }
    private var isMissing: Bool { !isLink && fileURL == nil }
    private var isPlaying: Bool { player.playingID == ref.id }

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 12) {
                leading
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    if let details {
                        Text(verbatim: details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if isMissing {
                        Text("attachments.missing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(ref.kind == .voiceNote ? .title2 : .body)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMissing)
        .task(id: fileURL) { await loadPreviewData() }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: Content

    /// User title, else the file name (files), host (links) or the localised kind name (photos, voice notes).
    var titleText: Text {
        if let title = ref.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return Text(verbatim: title)
        }
        switch ref.kind {
        case .file:
            if let name = ref.fileName { return Text(verbatim: name) }
        case .link:
            if let host = AttachmentLink.host(of: ref.url) ?? ref.url { return Text(verbatim: host) }
        default:
            break
        }
        return Text(LocalizedStringKey(DynamicL10nKeys.attachmentKind(ref.kind)))
    }

    private var details: String? {
        var parts: [String] = []
        if isLink {
            if let url = ref.url { parts.append(url) }
        } else {
            if ref.kind == .voiceNote, let duration {
                parts.append(Duration.seconds(duration.rounded()).formatted(.time(pattern: .minuteSecond)))
            }
            if let bytes = ref.byteCount, bytes > 0 {
                parts.append(bytes.formatted(.byteCount(style: .file).locale(locale)))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var leading: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary)
                Image(systemName: Self.symbol(for: ref))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trailingSymbol: String? {
        switch ref.kind {
        case .voiceNote: return isMissing ? nil : (isPlaying ? "pause.circle.fill" : "play.circle.fill")
        case .link: return "arrow.up.forward.square"
        default: return nil
        }
    }

    private var accessibilityValue: Text {
        guard ref.kind == .voiceNote, isPlaying else { return Text(verbatim: "") }
        return Text("attachments.voice.playing")
    }

    private var accessibilityHint: Text {
        switch ref.kind {
        case .link: return Text("attachments.hint.link")
        case .voiceNote: return Text(isPlaying ? "attachments.voice.pause" : "attachments.voice.play")
        default: return isMissing ? Text(verbatim: "") : Text("attachments.hint.preview")
        }
    }

    // MARK: Loading

    private var isImage: Bool {
        if ref.kind == .photo { return true }
        guard let type = ref.contentType.flatMap({ UTType($0) }) else { return false }
        return type.conforms(to: .image)
    }

    private func loadPreviewData() async {
        guard let fileURL else {
            thumbnail = nil
            duration = nil
            return
        }
        if isImage {
            thumbnail = await Self.thumbnail(of: fileURL, maxPixelSize: iconSize * displayScale)
        } else if ref.kind == .voiceNote {
            duration = await VoiceNotePlayer.duration(of: fileURL)
        }
    }

    /// A downsampled thumbnail (orientation applied), decoded off the main actor.
    nonisolated static func thumbnail(of url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        await Task.detached(priority: .utility) { () -> UIImage? in
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }.value
    }

    /// SF Symbol for an attachment without a thumbnail.
    static func symbol(for ref: AttachmentRef) -> String {
        switch ref.kind {
        case .link: return "link"
        case .voiceNote: return "waveform"
        case .photo: return "photo"
        default: break
        }
        guard let type = ref.contentType.flatMap({ UTType($0) }) else { return "doc" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .spreadsheet) { return "tablecells" }
        if type.conforms(to: .presentation) { return "play.rectangle" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}
