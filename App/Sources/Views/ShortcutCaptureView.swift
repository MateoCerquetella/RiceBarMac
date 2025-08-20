import SwiftUI
import AppKit

struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var shortcut: String
    var onCapture: (String) -> Void
    var autoSave: Bool = false
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = ShortcutTextField()
        textField.onShortcutCapture = { capturedShortcut in
            shortcut = capturedShortcut
            onCapture(capturedShortcut)
        }
        textField.autoSave = autoSave
        textField.stringValue = shortcut
        textField.isEditable = false
        textField.isBordered = true
        textField.placeholderString = "Click to record shortcut..."
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if let shortcutField = nsView as? ShortcutTextField {
            shortcutField.stringValue = shortcut
            shortcutField.autoSave = autoSave
        }
    }
}

class ShortcutTextField: NSTextField {
    var onShortcutCapture: ((String) -> Void)?
    var autoSave: Bool = false
    private var isRecording = false
    private var localMonitor: Any?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setup()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        focusRingType = .none
        isEditable = false
        isSelectable = false
        drawsBackground = true
        backgroundColor = NSColor.controlBackgroundColor
        textColor = NSColor.controlTextColor
        
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(startRecording))
        addGestureRecognizer(clickGesture)
    }
    
    @objc private func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        stringValue = "Press keys or Esc to cancel..."
        backgroundColor = NSColor.selectedControlColor
        textColor = NSColor.selectedControlTextColor
        
        // Start monitoring for key events
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil // Consume the event
        }
        
        // Stop recording if we lose focus or after a timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopRecording()
        }
        
        window?.makeFirstResponder(self)
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        if event.type == .keyDown {
            // Check for Escape key to cancel recording
            if event.keyCode == 53 { // Escape key
                stopRecording()
                return
            }
            
            // We have a key press, build the shortcut string
            let shortcutString = buildShortcutString(keyCode: event.keyCode, modifiers: modifiers)
            if !shortcutString.isEmpty {
                captureShortcut(shortcutString)
            }
        } else if event.type == .flagsChanged && modifiers.isEmpty {
            // All modifier keys were released without a key press
            stopRecording()
        }
    }
    
    private func buildShortcutString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        
        // Add modifiers in the correct order
        if modifiers.contains(.control) {
            parts.append("ctrl")
        }
        if modifiers.contains(.option) {
            parts.append("opt")
        }
        if modifiers.contains(.shift) {
            parts.append("shift")
        }
        if modifiers.contains(.command) {
            parts.append("cmd")
        }
        
        // Add the key
        if let keyString = keyCodeToString(keyCode) {
            parts.append(keyString)
            return parts.joined(separator: "+")
        }
        
        return ""
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        switch keyCode {
        // Numbers
        case 29: return "0"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        
        // Letters
        case 0: return "a"
        case 11: return "b"
        case 8: return "c"
        case 2: return "d"
        case 14: return "e"
        case 3: return "f"
        case 5: return "g"
        case 4: return "h"
        case 34: return "i"
        case 38: return "j"
        case 40: return "k"
        case 37: return "l"
        case 46: return "m"
        case 45: return "n"
        case 31: return "o"
        case 35: return "p"
        case 12: return "q"
        case 15: return "r"
        case 1: return "s"
        case 17: return "t"
        case 32: return "u"
        case 9: return "v"
        case 13: return "w"
        case 7: return "x"
        case 16: return "y"
        case 6: return "z"
        
        // Special keys
        case 36: return "return"
        case 48: return "tab"
        case 49: return "space"
        case 51: return "delete"
        case 53: return "escape"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        case 30: return "]"
        case 33: return "["
        case 43: return ","
        case 27: return "-"
        case 24: return "="
        case 42: return "\\"
        case 41: return ";"
        case 39: return "'"
        case 50: return "`"
        case 47: return "."
        case 44: return "/"
        
        // Function keys
        case 122: return "f1"
        case 120: return "f2"
        case 99: return "f3"
        case 118: return "f4"
        case 96: return "f5"
        case 97: return "f6"
        case 98: return "f7"
        case 100: return "f8"
        case 101: return "f9"
        case 109: return "f10"
        case 103: return "f11"
        case 111: return "f12"
        
        default: return nil
        }
    }
    
    private func captureShortcut(_ shortcut: String) {
        stringValue = shortcut
        onShortcutCapture?(shortcut)
        
        // Show brief success feedback
        if autoSave {
            let originalText = stringValue
            stringValue = "✓ Saved"
            backgroundColor = NSColor.systemGreen.withAlphaComponent(0.2)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.stringValue = originalText
                self?.backgroundColor = NSColor.controlBackgroundColor
                self?.stopRecording()
            }
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        backgroundColor = NSColor.controlBackgroundColor
        textColor = NSColor.controlTextColor
        
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        
        window?.makeFirstResponder(nil)
    }
    
    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }
    
    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}