import PhosphorUI
import SwiftUI

/// Entry point.
///
/// One window, no menu bar extras, no background agents: everything the app
/// does happens because you asked for it.
@main
struct PhosphorApp: App {
    var body: some Scene {
        Window("Phosphor", id: "main") {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_240, height: 800)
    }
}
