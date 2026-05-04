import XCTest
@testable import JustDoThree

@MainActor
final class SpeechDictationControllerTests: XCTestCase {
    func test_start_whenAuthorized_entersRecordingState() {
        let fake = FakeSpeechRecognizer()
        fake.stubAuth = .authorized
        let controller = SpeechDictationController(recognizer: fake)

        controller.start()

        XCTAssertEqual(controller.state, .recording)
        XCTAssertEqual(fake.startCallCount, 1)
    }
}
