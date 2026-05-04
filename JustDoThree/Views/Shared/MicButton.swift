import SwiftUI

struct MicButton: View {
    @Binding var text: String
    var onFinished: () -> Void = {}

    @StateObject private var controller: SpeechDictationController
    @State private var pulse = false
    @State private var showPermissionAlert = false

    init(text: Binding<String>, onFinished: @escaping () -> Void = {}) {
        self._text = text
        self.onFinished = onFinished
        self._controller = StateObject(
            wrappedValue: SpeechDictationController(recognizer: AppleSpeechRecognizer())
        )
    }

    var body: some View {
        Button(action: tapped) {
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .foregroundStyle(isRecording ? .red : .accentColor)
                .scaleEffect(pulse ? 1.15 : 1.0)
                .animation(
                    isRecording
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop dictation" : "Start dictation")
        .onChange(of: controller.transcript) { _, new in
            if isRecording { text = new }
        }
        .onChange(of: controller.state) { _, new in
            switch new {
            case .recording:
                pulse = true
            case .idle:
                pulse = false
                onFinished()
            case .error(let msg):
                pulse = false
                if msg.contains("Permission") { showPermissionAlert = true }
            case .requestingAuth:
                break
            }
        }
        .alert("Microphone access needed",
               isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable Microphone and Speech Recognition for Just Do Three to use dictation.")
        }
    }

    private var isRecording: Bool { controller.state == .recording }

    private func tapped() {
        if isRecording { controller.stop() } else { controller.start() }
    }
}
