import AppKit
import Carbon
import TranslationCore

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32 = UInt32(kVK_ANSI_E)
    var modifiers: UInt32 = UInt32(cmdKey | shiftKey)
    var keyLabel: String = "E"

    var label: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }

    init() {}
    static var chinese: Shortcut {
        var value = Shortcut()
        value.keyCode = UInt32(kVK_ANSI_C)
        value.keyLabel = "C"
        return value
    }
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty,
              let text = event.charactersIgnoringModifiers, !text.isEmpty,
              ![UInt16(kVK_Escape), UInt16(kVK_Return), UInt16(kVK_Tab), UInt16(kVK_Delete)].contains(event.keyCode) else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        keyLabel = text.uppercased()
    }
}

@MainActor
final class Preferences {
    private let defaults = UserDefaults.standard
    var profiles: ProfileCollection {
        get {
            guard let data = defaults.data(forKey: "llmProfiles"),
                  let value = try? JSONDecoder().decode(ProfileCollection.self, from: data) else {
                let initial = ProfileCollection.initial()
                defaults.set(try? JSONEncoder().encode(initial), forKey: "llmProfiles")
                return initial
            }
            return value
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "llmProfiles") }
    }
    var shortcut: Shortcut {
        get {
            guard let data = defaults.data(forKey: "shortcut"),
                  let value = try? JSONDecoder().decode(Shortcut.self, from: data) else { return .init() }
            return value
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "shortcut") }
    }
    var chineseShortcut: Shortcut {
        get {
            guard let data = defaults.data(forKey: "chineseShortcut"),
                  let value = try? JSONDecoder().decode(Shortcut.self, from: data) else { return .chinese }
            return value
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "chineseShortcut") }
    }
    var indicatorOrigin: NSPoint? {
        get {
            guard defaults.object(forKey: "indicatorX") != nil else { return nil }
            return NSPoint(x: defaults.double(forKey: "indicatorX"), y: defaults.double(forKey: "indicatorY"))
        }
        set {
            defaults.set(newValue?.x, forKey: "indicatorX")
            defaults.set(newValue?.y, forKey: "indicatorY")
        }
    }
    var hasCompletedSetup: Bool {
        get { defaults.bool(forKey: "hasCompletedSetup") }
        set { defaults.set(newValue, forKey: "hasCompletedSetup") }
    }
}
