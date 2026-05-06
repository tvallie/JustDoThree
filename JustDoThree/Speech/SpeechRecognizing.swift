import Foundation

enum SpeechAuthState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum DictationState: Equatable {
    case idle
    case requestingAuth
    case recording
    case error(String)
}

protocol SpeechRecognizing: AnyObject {
    var isAvailable: Bool { get }

    func requestAuthorization(_ completion: @escaping (SpeechAuthState) -> Void)

    func start(
        onPartial: @escaping (String) -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    )

    func stop()
}
