import Foundation
import SwiftData
import WatchConnectivity

#if os(iOS)

/// Phone-side WCSession delegate. Owns the singleton WCSession and routes
/// incoming watch messages to PhoneSyncHandler. Phone push-side (snapshot
/// delivery via updateApplicationContext) is also funneled here so callers
/// don't need to know about WCSession directly.
final class PhoneWCDelegate: NSObject, WCSessionDelegate {
    static let shared = PhoneWCDelegate()

    private let queue = DispatchQueue(label: "com.todd.justdothree.wc-phone")
    private var handler: PhoneSyncHandler?

    private override init() {
        super.init()
    }

    /// Activates the session if WatchConnectivity is supported on this device.
    /// `containerProvider` is called lazily on the main actor when a message
    /// arrives, so we don't capture a ModelContainer that may not be ready
    /// at activation time.
    func activate(containerProvider: @MainActor @escaping () -> ModelContainer) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        Task { @MainActor in
            self.handler = PhoneSyncHandler(container: containerProvider())
        }
    }

    /// Encode and push a snapshot to the watch via updateApplicationContext.
    /// Only the latest context is delivered if the watch is asleep.
    func push(snapshot: TodaySnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try session.updateApplicationContext(["snapshot": data])
        } catch {
            #if DEBUG
            print("[PhoneWCDelegate] Failed to push snapshot: \(error)")
            #endif
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        #if DEBUG
        if let error {
            print("[PhoneWCDelegate] activation error: \(error)")
        } else {
            print("[PhoneWCDelegate] activation state: \(activationState.rawValue)")
        }
        #endif
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so the session stays alive across watch swaps.
        WCSession.default.activate()
    }

    /// Watch sent a sendMessage with no reply expected.
    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any]) {
        dispatch(payload: message)
    }

    /// Watch sent transferUserInfo for offline-tolerant delivery.
    func session(_ session: WCSession,
                 didReceiveUserInfo userInfo: [String: Any] = [:]) {
        dispatch(payload: userInfo)
    }

    private func dispatch(payload: [String: Any]) {
        Task { @MainActor [weak self] in
            guard let self, let handler = self.handler else { return }
            do {
                if let data = payload["completion"] as? Data {
                    let cmd = try CompletionCommand.decodeCompatible(from: data)
                    try handler.apply(cmd)
                } else if let data = payload["intentResult"] as? Data {
                    let result = try WatchIntentResult.decodeCompatible(from: data)
                    try handler.apply(result)
                }
            } catch {
                #if DEBUG
                print("[PhoneWCDelegate] Failed to handle payload: \(error)")
                #endif
            }
        }
    }
}

#endif
