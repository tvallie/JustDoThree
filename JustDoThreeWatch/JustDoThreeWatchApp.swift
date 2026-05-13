import SwiftUI
import SwiftData

@main
struct JustDoThreeWatchApp: App {
    /// Watch-local SwiftData store, separate from the phone's. The phone is
    /// the source of truth; the watch caches the slice it needs.
    private let container: ModelContainer = {
        let url = URL.documentsDirectory.appending(path: "jdt-watch.store")
        return JDTModelContainer.make(url: url)
    }()

    init() {
        let container = self.container
        // Route shared-code paths (App Intents, BacklogInsert) to the
        // watch's own store rather than the framework default.
        JDTModelContainer.current = container
        WatchWCDelegate.shared.activate(storeProvider: {
            WatchSyncStore(container: container)
        })
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
