// "Import Timetable" from a photo, scan or PDF (Phase 9 I2; entry points: onboarding, the timetables manager, the
// Timetable ⋯ menu, Settings › Import). One sheet, one NavigationStack:
//   capture → (PDF page) → processing → review → Approve → ShareImportPreview (Add as New / Replace with backup)
// Presenters (document camera, photo picker, file importer, alerts) hang on the stack, never on a Form Section
// (RISKS #99). While the review holds edits, swipe-to-dismiss is off and a deep link waits (`protectsUnsavedWork`).
// HIG: sheets.md, privacy.md (camera asked in context; the picker and Files need no permission), generative-ai.md
// ("Uses Apple Intelligence on this iPhone" only when it is really used), loading.md.
// APIs: View.photosPicker(isPresented:selection:matching:), PhotosPickerItem.loadTransferable(type: Data.self),
//   View.fileImporter(isPresented:allowedContentTypes:onCompletion:), View.fullScreenCover(isPresented:),
//   AVCaptureDevice.authorizationStatus(for: .video).
import AVFoundation
import PhotosUI
import SwiftUI
import TimetableCore
import TimetableUI
import UniformTypeIdentifiers

struct PhotoImportView: View {
    /// Set when importing from onboarding: the school type chosen there.
    let profile: UserProfile?

    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var flow: PhotoImportModel
    @State private var scanning = false
    @State private var choosingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var choosingFile = false
    @State private var cameraDenied = false

    /// `flow` lets the DEBUG screenshot routes start in a later stage.
    init(profile: UserProfile? = nil, flow: PhotoImportModel = PhotoImportModel()) {
        self.profile = profile
        _flow = State(initialValue: flow)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            if flow.stage == .processing { flow.cancel() } else { dismiss() }
                        } label: { Text("editor.common.cancel") }
                    }
                }
        }
        .interactiveDismissDisabled(flow.stage == .review || flow.stage == .processing)
        .protectsUnsavedWork(flow.stage == .review)
        .fullScreenCover(isPresented: $scanning) {
            DocumentCameraView { image in
                scanning = false
                start(.image(image))
            } onCancel: { failed in
                scanning = false
                if failed { flow.problemKey = "import.error.camera" }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    flow.problemKey = "import.error.unreadable"
                    return
                }
                start(.imageData(data))
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image, .pdf]) { result in
            guard case .success(let url) = result, let data = ImportImageLoader.readPicked(url) else {
                if case .failure = result { flow.problemKey = "import.error.unreadable" }
                return
            }
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                flow.open(pdf: data, knownSubjects: knownSubjects, defaultName: defaultName)
            } else {
                start(.imageData(data))
            }
        }
        .alert(Text("import.error.title"), isPresented: Binding(get: { flow.problemKey != nil },
                                                                set: { if !$0 { flow.problemKey = nil } })) {
            Button { } label: { Text("editor.warnings.ok") }
        } message: {
            if let key = flow.problemKey { Text(LocalizedStringKey(key)) }
        }
        .alert(Text("share.import.camera.title"), isPresented: $cameraDenied) {
            Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: {
                Text("health.action.openSettings")
            }
            Button(role: .cancel) { } label: { Text("editor.common.cancel") }
        } message: {
            Text("import.camera.denied")
        }
    }

    private var title: LocalizedStringKey {
        switch flow.stage {
        case .capture: return "import.capture.title"
        case .choosingPage: return "import.pdf.pages.title"
        case .processing: return "import.processing.title"
        case .review: return "import.review.title"
        }
    }

    @ViewBuilder private var content: some View {
        switch flow.stage {
        case .capture:
            ImportCaptureChoices(scan: scan, choosePhoto: { choosingPhoto = true }, chooseFile: { choosingFile = true }) {
                #if DEBUG
                ImportSampleSection { start(.image($0)) }
                #endif
            }
        case .choosingPage(let data):
            ImportPDFPagePicker(data: data) { page in start(.pdf(data, page: page)) }
        case .processing:
            ImportProcessingView(image: flow.image, step: flow.step, usesAppleIntelligence: flow.usedAppleIntelligence)
        case .review:
            ImportReviewScreen(flow: flow, profile: profile) { imported in
                if imported { navigation.selectedTab = .timetable }
                dismiss()
            }
        }
    }

    // MARK: Actions

    private func scan() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: cameraDenied = true
        default: scanning = true   // .notDetermined: the document camera asks
        }
    }

    private func start(_ source: PhotoImportModel.Source) {
        flow.start(source, knownSubjects: knownSubjects, defaultName: defaultName)
    }

    private var knownSubjects: [String] {
        guard let database = model.database else { return [] }
        return database.subjects.filter { !$0.isDeleted }.map(\.name)
    }

    private var defaultName: String { model.renderer.string(forKey: "import.review.defaultName") }
}

// MARK: - Capture choices

/// The first screen: what the import does and the three sources.
private struct ImportCaptureChoices<Extra: View>: View {
    let scan: () -> Void
    let choosePhoto: () -> Void
    let chooseFile: () -> Void
    @ViewBuilder let extra: Extra
    @State private var aiStatus = AppleIntelligenceStatus.current
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Form {
            // At accessibility sizes the sources come first: the intro alone would fill the screen.
            if typeSize.isAccessibilitySize { sources; intro } else { intro; sources }
            extra
        }
    }

    private var intro: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "tablecells")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Color.ink)
                    .accessibilityHidden(true)
                Text("import.capture.headline")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("import.capture.message")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private var sources: some View {
        Section {
            if DocumentCameraView.isSupported {
                Button(action: scan) {
                    Label { Text("import.capture.scan") } icon: { Image(systemName: "doc.viewfinder") }
                }
            }
            Button(action: choosePhoto) {
                Label { Text("import.capture.photo") } icon: { Image(systemName: "photo.on.rectangle") }
            }
            Button(action: chooseFile) {
                Label { Text("import.capture.file") } icon: { Image(systemName: "folder") }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("import.capture.footer")
                if aiStatus == .available {
                    Label { Text("import.capture.ai") } icon: { Image(systemName: "sparkles") }
                }
            }
        }
    }
}
