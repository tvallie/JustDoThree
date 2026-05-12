import Foundation
import SwiftData

/// Single shared SwiftData container used by the app scene and any AppIntents.
/// Keeping one container ensures app and Siri-invoked intents read/write the
/// same on-disk store with the same schema configuration.
enum JDTModelContainer {
    static let shared: ModelContainer = make(url: nil)

    /// Build a container, optionally backed by a specific store URL.
    /// Passing `nil` uses the default SwiftData store location for the host app.
    /// The watch target supplies its own URL so it gets a separate local store.
    static func make(url: URL?) -> ModelContainer {
        do {
            let config: ModelConfiguration
            if let url {
                config = ModelConfiguration(url: url)
            } else {
                config = ModelConfiguration()
            }
            return try ModelContainer(
                for: JDTask.self, DailyPlan.self, CompletionLog.self,
                configurations: config
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
