import Foundation
@testable import JustDoThree

final class FakeSpeechRecognizer: SpeechRecognizing {
    var isAvailable = true

    var stubAuth: SpeechAuthState = .authorized
    var startCallCount = 0
    var stopCallCount = 0

    private var partialHandler: ((String) -> Void)?
    private var finishHandler: (() -> Void)?
    private var errorHandler: ((Error) -> Void)?

    func requestAuthorization(_ completion: @escaping (SpeechAuthState) -> Void) {
        completion(stubAuth)
    }

    func start(
        onPartial: @escaping (String) -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        startCallCount += 1
        partialHandler = onPartial
        finishHandler = onFinish
        errorHandler = onError
    }

    func stop() {
        stopCallCount += 1
        finishHandler?()
    }

    func emitPartial(_ text: String) { partialHandler?(text) }
    func emitError(_ err: Error) { errorHandler?(err) }
}
