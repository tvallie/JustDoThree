import Foundation

/// On watchOS, forward a freshly-inserted backlog task to the phone so it
/// lands in the canonical backlog there too. No-op on iOS (the intent
/// already ran against the canonical store).
@MainActor
func forwardToPhoneIfOnWatch(inserted: InsertedBacklogTask,
                             list: WatchIntentResult.List) {
    #if os(watchOS)
    WatchWCDelegate.shared.send(intentResult: WatchIntentResult(
        schemaVersion: SyncSchema.current,
        clientID: inserted.id,
        list: list,
        title: inserted.title,
        createdAt: Date()
    ))
    #endif
}
