// Sheet for recording a voice-note attachment (stage B3). Record / Stop, elapsed time, Save hands the temporary .m4a
// to the caller (which copies it into the attachment store), Cancel deletes it. Microphone permission is asked on the
// first tap of Record; when denied, an alert offers the app's Settings page.
// APIs: TimelineView(.periodic(from:by:)), UIApplication.openSettingsURLString, interactiveDismissDisabled(_:).
import SwiftUI
import UIKit

struct VoiceNoteRecorderSheet: View {
    /// Receives the finished recording's temporary file (the receiver deletes it after copying).
    let onSave: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var recorder = VoiceNoteRecorder()
    @State private var showDenied = false
    @State private var showFailed = false
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(verbatim: Duration.seconds(recorder.elapsed(at: context.date).rounded(.down))
                        .formatted(.time(pattern: .minuteSecond)))
                        .font(.largeTitle.monospacedDigit())
                        .accessibilityLabel(Text("attachments.voice.elapsed"))
                        .accessibilityValue(Text(verbatim: Duration.seconds(recorder.elapsed(at: context.date).rounded(.down))
                            .formatted(.units(allowed: [.minutes, .seconds], width: .wide))))
                }
                Button {
                    toggleRecording()
                } label: {
                    Label {
                        Text(recorder.isRecording ? "attachments.voice.stop" : "attachments.voice.record")
                    } icon: {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    }
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .accentColor)
                .disabled(isStarting)
                Text("attachments.voice.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding()
            .navigationTitle(Text("attachments.voice.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("editor.common.cancel") {
                        recorder.discard()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("editor.common.save") {
                        if let url = recorder.take() { onSave(url) }
                        dismiss()
                    }
                    .disabled(recorder.recordedURL == nil)
                }
            }
            .alert(Text("attachments.voice.denied.title"), isPresented: $showDenied) {
                Button("attachments.voice.openSettings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("editor.common.cancel", role: .cancel) {}
            } message: {
                Text("attachments.voice.denied.message")
            }
            .alert(Text("attachments.voice.failed"), isPresented: $showFailed) {
                Button("editor.common.cancel", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(recorder.isRecording || recorder.recordedURL != nil)
        .onDisappear { recorder.discard() }   // no-op after Save (take() released the file)
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
            return
        }
        isStarting = true
        Task {
            let failure = await recorder.start()
            isStarting = false
            switch failure {
            case .denied?: showDenied = true
            case .failed?: showFailed = true
            case nil: break
            }
        }
    }
}
