import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1600, height: 1000),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "RiceBarMac Settings"
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.isReleasedWhenClosed = false
        
        // Set minimum and maximum size constraints
        window.minSize = NSSize(width: 800, height: 600)
        window.maxSize = NSSize(width: 2000, height: 1400)
        
        let settingsView = SettingsWindow()
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView
        
        self.init(window: window)
    }
    
    func showSettings() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}