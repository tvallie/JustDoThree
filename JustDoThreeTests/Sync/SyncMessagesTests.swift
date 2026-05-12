import XCTest
@testable import JustDoThree

final class SyncMessagesTests: XCTestCase {
    func test_todaySnapshot_roundtrip() throws {
        let snap = TodaySnapshot(
            schemaVersion: SyncSchema.current,
            planDate: Date(timeIntervalSince1970: 1_700_000_000),
            today: [
                .init(id: UUID(), title: "A", isCompleted: false, isStretch: false),
                .init(id: UUID(), title: "B", isCompleted: true,  isStretch: true)
            ],
            work: [.init(id: UUID(), title: "W", isCompleted: false, isStretch: false)],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(TodaySnapshot.self, from: data)
        XCTAssertEqual(snap, back)
    }

    func test_completionCommand_roundtrip() throws {
        let cmd = CompletionCommand(
            schemaVersion: SyncSchema.current,
            taskID: UUID(),
            action: .complete,
            issuedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let data = try JSONEncoder().encode(cmd)
        let back = try JSONDecoder().decode(CompletionCommand.self, from: data)
        XCTAssertEqual(cmd, back)
    }

    func test_intentResult_roundtrip() throws {
        let result = WatchIntentResult(
            schemaVersion: SyncSchema.current,
            clientID: UUID(),
            list: .personalBacklog,
            title: "Pick up milk",
            createdAt: Date(timeIntervalSince1970: 1_700_000_300)
        )
        let data = try JSONEncoder().encode(result)
        let back = try JSONDecoder().decode(WatchIntentResult.self, from: data)
        XCTAssertEqual(result, back)
    }

    func test_completionCommand_decodeCompatible_rejects_unknown_schema() throws {
        let badPayload = #"{"schemaVersion":99,"taskID":"\#(UUID().uuidString)","action":"complete","issuedAt":0}"#
        let data = badPayload.data(using: .utf8)!
        XCTAssertThrowsError(try CompletionCommand.decodeCompatible(from: data)) { error in
            guard case SyncDecodeError.unsupportedSchemaVersion(let v) = error else {
                return XCTFail("Expected unsupportedSchemaVersion, got \(error)")
            }
            XCTAssertEqual(v, 99)
        }
    }

    func test_completionCommand_decodeCompatible_accepts_current_schema() throws {
        let cmd = CompletionCommand(
            schemaVersion: SyncSchema.current,
            taskID: UUID(), action: .uncomplete,
            issuedAt: Date()
        )
        let data = try JSONEncoder().encode(cmd)
        let decoded = try CompletionCommand.decodeCompatible(from: data)
        XCTAssertEqual(decoded, cmd)
    }
}
