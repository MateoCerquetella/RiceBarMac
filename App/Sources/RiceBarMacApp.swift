import SwiftUI
import AppKit

@main
struct RiceBarMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Button("Open Profiles Folder") {
                ProfileManager.shared.openProfilesFolder()
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
