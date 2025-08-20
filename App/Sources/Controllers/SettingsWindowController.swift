import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 450),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "RiceBarMac Settings"
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.isReleasedWhenClosed = false
        
        // Set minimum and maximum size constraints
        window.minSize = NSSize(width: 480, height: 400)
        window.maxSize = NSSize(width: 800, height: 800)
        
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