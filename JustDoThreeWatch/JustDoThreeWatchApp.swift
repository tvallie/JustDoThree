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

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
