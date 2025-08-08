import Foundation
#if canImport(AppKit)
import AppKit
#endif
import HotKey

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotkeys: [HotKey] = []

    private init() {}

    func registerHotKeys(profiles: [ProfileDescriptor], onTrigger: @escaping (ProfileDescriptor) -> Void) {
        hotkeys.removeAll()
        for descriptor in profiles {
            guard let comboString = descriptor.profile.hotkey, let combo = parse(comboString) else { continue }
            let hotKey = HotKey(keyCombo: combo)
            hotKey.keyDownHandler = { onTrigger(descriptor) }
            hotkeys.append(hotKey)
        }
    }

    private func parse(_ string: String) -> KeyCombo? {
        // e.g. "ctrl+cmd+1" or "cmd+option+a"
        let parts = string.lowercased().split(separator: "+").map { String($0) }
        guard !parts.isEmpty else { return nil }
        var modifiers: NSEvent.ModifierFlags = []
        var keyString: String?
        for part in parts {
            switch part {
            case "ctrl", "control": modifiers.insert(.control)
            case "cmd", "command": modifiers.insert(.command)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            default: keyString = part
            }
        }
        guard let keyString else { return nil }
        guard let key = mapKey(keyString) else { return nil }
        return KeyCombo(key: key, modifiers: modifiers)
    }

    private func mapKey(_ s: String) -> Key? {
        if let number = Int(s), (0...9).contains(number) {
            switch number {
            case 0: return .zero
            case 1: return .one
            case 2: return .two
            case 3: return .three
            case 4: return .four
            case 5: return .five
            case 6: return .six
            case 7: return .seven
            case 8: return .eight
            case 9: return .nine
            default: break
            }
        }
        if s.count == 1, let c = s.uppercased().unicodeScalars.first {
            switch c {
            case "A": return .a
            case "B": return .b
            case "C": return .c
            case "D": return .d
            case "E": return .e
            case "F": return .f
            case "G": return .g
            case "H": return .h
            case "I": return .i
            case "J": return .j
            case "K": return .k
            case "L": return .l
            case "M": return .m
            case "N": return .n
            case "O": return .o
            case "P": return .p
            case "Q": return .q
            case "R": return .r
            case "S": return .s
            case "T": return .t
            case "U": return .u
            case "V": return .v
            case "W": return .w
            case "X": return .x
            case "Y": return .y
            case "Z": return .z
            default: break
            }
        }
        switch s {
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "up": return .upArrow
        case "down": return .downArrow
        default: return nil
        }
    }
}
