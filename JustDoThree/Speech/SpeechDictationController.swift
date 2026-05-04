import Foundation
import Combine

@MainActor
final class SpeechDictationController: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var transcript: String = ""

    private let recognizer: SpeechRecognizing

    init(recognizer: SpeechRecognizing) {
        self.recognizer = recognizer
    }

    nonisolated func start() {
        MainActor.assumeIsolated { self.state = .requestingAuth }
        recognizer.requestAuthorization { [weak self] auth in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard auth == .authorized else {
                    self.state = .error("Permission denied")
                    return
                }
                self.transcript = ""
                self.recognizer.start(
                    requireOnDevice: self.recognizer.supportsOnDevice,
                    onPartial: { [weak self] text in
                        MainActor.assumeIsolated { self?.transcript = text }
                    },
                    onFinish: { [weak self] in
                        MainActor.assumeIsolated { self?.state = .idle }
                    },
                    onError: { [weak self] err in
                        MainActor.assumeIsolated { self?.state = .error(err.localizedDescription) }
                    }
                )
                self.state = .recording
            }
        }
    }

    func stop() {
        recognizer.stop()
    }
}
