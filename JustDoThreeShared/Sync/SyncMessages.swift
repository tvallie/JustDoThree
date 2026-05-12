import Foundation

/// Schema version for the WatchConnectivity sync payloads. Bump when the
/// shape of any sync message changes in a backward-incompatible way. Both
/// sides reject messages with a different version.
enum SyncSchema {
    static let current: Int = 1
}

/// Phone → Watch snapshot of what the watch needs to render today.
struct TodaySnapshot: Codable, Equatable {
    struct Row: Codable, Equatable {
        let id: UUID
        let title: String
        let isCompleted: Bool
        /// True for stretch tasks (the 4th-onward items in today's plan).
        let isStretch: Bool
    }

    let schemaVersion: Int
    let planDate: Date
    let today: [Row]
    let work: [Row]
    let generatedAt: Date

    static func decodeCompatible(from data: Data) throws -> TodaySnapshot {
        let value = try JSONDecoder().decode(TodaySnapshot.self, from: data)
        try SyncSchema.validate(value.schemaVersion)
        return value
    }
}

/// Watch → Phone command to toggle completion on a single task. The phone
/// applies via PlannerEngine so recurring / stretch logic stays in one place.
struct CompletionCommand: Codable, Equatable {
    enum Action: String, Codable {
        case complete
        case uncomplete
    }

    let schemaVersion: Int
    let taskID: UUID
    let action: Action
    let issuedAt: Date

    static func decodeCompatible(from data: Data) throws -> CompletionCommand {
        let value = try JSONDecoder().decode(CompletionCommand.self, from: data)
        try SyncSchema.validate(value.schemaVersion)
        return value
    }
}

/// Watch → Phone notification that an App Intent ran on the watch and a
/// new task should appear in the phone's backlog. Phone dedupes by `clientID`.
struct WatchIntentResult: Codable, Equatable {
    enum List: String, Codable {
        case personalBacklog
        case workBacklog
    }

    let schemaVersion: Int
    let clientID: UUID
    let list: List
    let title: String
    let createdAt: Date

    static func decodeCompatible(from data: Data) throws -> WatchIntentResult {
        let value = try JSONDecoder().decode(WatchIntentResult.self, from: data)
        try SyncSchema.validate(value.schemaVersion)
        return value
    }
}

enum SyncDecodeError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

private extension SyncSchema {
    static func validate(_ version: Int) throws {
        guard version == current else {
            throw SyncDecodeError.unsupportedSchemaVersion(version)
        }
    }
}
