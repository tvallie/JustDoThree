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

    func test_start_whenDenied_entersErrorState_andDoesNotStartRecognizer() {
        let fake = FakeSpeechRecognizer()
        fake.stubAuth = .denied
        let controller = SpeechDictationController(recognizer: fake)

        controller.start()

        if case .error = controller.state {} else {
            XCTFail("Expected error state, got \(controller.state)")
        }
        XCTAssertEqual(fake.startCallCount, 0)
    }

    func test_partialResults_updateTranscript() {
        let fake = FakeSpeechRecognizer()
        let controller = SpeechDictationController(recognizer: fake)
        controller.start()

        fake.emitPartial("buy")
        XCTAssertEqual(controller.transcript, "buy")

        fake.emitPartial("buy milk")
        XCTAssertEqual(controller.transcript, "buy milk")
    }

    func test_stop_returnsToIdle() {
        let fake = FakeSpeechRecognizer()
        let controller = SpeechDictationController(recognizer: fake)
        controller.start()
        XCTAssertEqual(controller.state, .recording)

        controller.stop()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(fake.stopCallCount, 1)
    }

    func test_recognizerError_movesControllerToErrorState() {
        let fake = FakeSpeechRecognizer()
        let controller = SpeechDictationController(recognizer: fake)
        controller.start()

        fake.emitError(NSError(domain: "test", code: 1))

        if case .error = controller.state {} else {
            XCTFail("Expected error state, got \(controller.state)")
        }
    }
}
