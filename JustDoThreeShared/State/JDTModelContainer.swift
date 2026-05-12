import Foundation
import SwiftData

/// Single shared SwiftData container used by the app scene and any AppIntents.
/// Keeping one container ensures app and Siri-invoked intents read/write the
/// same on-disk store with the same schema configuration.
enum JDTModelContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: JDTask.self, DailyPlan.self, CompletionLog.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
