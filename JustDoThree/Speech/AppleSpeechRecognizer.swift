import Foundation
import Speech
import AVFoundation

final class AppleSpeechRecognizer: SpeechRecognizing {
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    func requestAuthorization(_ completion: @escaping (SpeechAuthState) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            AVAudioApplication.requestRecordPermission { micGranted in
                let mapped: SpeechAuthState
                switch (speechStatus, micGranted) {
                case (.authorized, true): mapped = .authorized
                case (.denied, _), (_, false): mapped = .denied
                case (.restricted, _): mapped = .restricted
                default: mapped = .notDetermined
                }
                DispatchQueue.main.async { completion(mapped) }
            }
        }
    }

    func start(
        onPartial: @escaping (String) -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let recognizer, recognizer.isAvailable else {
            onError(NSError(domain: "AppleSpeechRecognizer", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Speech recognition is unavailable."]))
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            self.request = req

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                req.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    onPartial(text)
                    self.resetSilenceTimer(onFinish: onFinish)
                }
                if let error {
                    self.cleanup()
                    onError(error)
                } else if result?.isFinal == true {
                    self.cleanup()
                    onFinish()
                }
            }
            resetSilenceTimer(onFinish: onFinish)
        } catch {
            cleanup()
            onError(error)
        }
    }

    func stop() {
        cleanup()
    }

    private func resetSilenceTimer(onFinish: @escaping () -> Void) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.cleanup()
            onFinish()
        }
    }

    private func cleanup() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
