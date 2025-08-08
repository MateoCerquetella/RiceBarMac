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
    @AppStorage("devMode") private var devMode: Bool = true

    var body: some View {
        Form {
            Toggle("Developer Mode (disable sandbox behaviors)", isOn: $devMode)
                .toggleStyle(.switch)
            Button("Open Profiles Folder") {
                ProfileManager.shared.openProfilesFolder()
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
