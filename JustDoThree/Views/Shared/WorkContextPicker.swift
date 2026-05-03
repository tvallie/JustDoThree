import SwiftUI

/// A `Personal | Work` segmented picker placed in the nav bar principal slot.
/// Invisible when `workModeEnabled` is false — callers can render it unconditionally.
struct WorkContextPicker: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.workModeEnabled {
            Picker(
                "Context",
                selection: Binding(
                    get: { appState.activeContext },
                    set: { appState.activeContext = $0 }
                )
            ) {
                Text("Personal").tag(false)
                Text("Work").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
    }
}
