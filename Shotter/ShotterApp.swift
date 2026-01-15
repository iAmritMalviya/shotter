import SwiftUI

@main
struct ShotterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene for Preferences window (Cmd+,)
        Settings {
            PreferencesView()
        }
    }
}
