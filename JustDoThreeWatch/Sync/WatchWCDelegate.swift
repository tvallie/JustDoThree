import Foundation
import SwiftData
import WatchConnectivity

#if os(watchOS)

/// Watch-side WCSession delegate. Receives TodaySnapshot via
/// updateApplicationContext, sends CompletionCommand / WatchIntentResult
/// back to the phone.
final class WatchWCDelegate: NSObject, WCSessionDelegate {
    static let shared = WatchWCDelegate()

    private var store: WatchSyncStore?

    private override init() {
        super.init()
    }

    /// Activate the session. `storeProvider` is called once we're on the
    /// MainActor to materialize the watch's WatchSyncStore.
    func activate(storeProvider: @MainActor @escaping () -> WatchSyncStore) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        Task { @MainActor in
            self.store = storeProvider()
            // If the phone has already delivered a context before we wired
            // the store up, apply whatever's pending now.
            self.applyIfPending()
        }
    }

    // MARK: - Outgoing commands

    func send(completion cmd: CompletionCommand) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard let data = try? JSONEncoder().encode(cmd) else { return }
        if session.isReachable {
            session.sendMessage(["completion": data], replyHandler: nil) { error in
                #if DEBUG
                print("[WatchWCDelegate] sendMessage failed, falling back to transferUserInfo: \(error)")
                #endif
                session.transferUserInfo(["completion": data])
            }
        } else {
            session.transferUserInfo(["completion": data])
        }
    }

    func send(intentResult result: WatchIntentResult) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard let data = try? JSONEncoder().encode(result) else { return }
        if session.isReachable {
            session.sendMessage(["intentResult": data], replyHandler: nil) { error in
                #if DEBUG
                print("[WatchWCDelegate] sendMessage failed, falling back to transferUserInfo: \(error)")
                #endif
                session.transferUserInfo(["intentResult": data])
            }
        } else {
            session.transferUserInfo(["intentResult": data])
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        #if DEBUG
        if let error {
            print("[WatchWCDelegate] activation error: \(error)")
        }
        #endif
        Task { @MainActor in
            self.applyIfPending()
        }
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["snapshot"] as? Data else { return }
        Task { @MainActor in
            self.applySnapshot(data: data)
        }
    }

    // MARK: - Helpers

    @MainActor
    private func applyIfPending() {
        // updateApplicationContext leaves the most recent context on
        // WCSession.receivedApplicationContext; replay it on activation
        // and on store-readiness.
        let ctx = WCSession.default.receivedApplicationContext
        guard let data = ctx["snapshot"] as? Data else { return }
        applySnapshot(data: data)
    }

    @MainActor
    private func applySnapshot(data: Data) {
        guard let store else { return }
        do {
            let snap = try TodaySnapshot.decodeCompatible(from: data)
            try store.apply(snap)
        } catch {
            #if DEBUG
            print("[WatchWCDelegate] Failed to apply snapshot: \(error)")
            #endif
        }
    }
}

#endif
