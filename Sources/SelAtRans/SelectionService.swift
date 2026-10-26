import AppKit
import ApplicationServices
import Carbon
import TranslationCore

struct CapturedInput {
    let text: String
    let snapshot: TextSnapshot?
    let element: AXUIElement?
    let window: AXUIElement?
}

enum SelectionError: Error, LocalizedError {
    case permission, secureInput, contextChanged, copyUnavailable, modifiersHeld
    var errorDescription: String? {
        switch self {
        case .permission: return "请在系统设置 → 隐私与安全性 → 辅助功能中允许 SelAtRans。"
        case .secureInput: return "当前处于安全输入状态，未读取或发送文字。"
        case .contextChanged: return "读取文字时焦点发生变化，请重新选择后重试。"
        case .copyUnavailable: return "无法读取选中文字，请先手动复制，再按快捷键。"
        case .modifiersHeld: return "请松开快捷键后重试。"
        }
    }
}

@MainActor
final class SelectionService {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func capture() async throws -> CapturedInput {
        guard isTrusted else { throw SelectionError.permission }
        guard !IsSecureEventInputEnabled() else { throw SelectionError.secureInput }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw SelectionError.contextChanged }
        let pid = app.processIdentifier
        let focus = focusedElement()
        if let focus, isSecure(focus) { throw SelectionError.secureInput }
        // Synthetic copy must not inherit the user's still-held Shift modifier.
        for _ in 0..<40 {
            if NSEvent.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        guard NSEvent.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else {
            throw SelectionError.modifiersHeld
        }
        guard sameFocus(pid: pid, original: focus), !IsSecureEventInputEnabled() else { throw SelectionError.contextChanged }

        if let focus, let selected = string(focus, kAXSelectedTextAttribute), !selected.isEmpty {
            return input(text: selected, element: focus, pid: pid)
        }
        let clipboardText = NSPasteboard.general.string(forType: .string)
        // An editable field with an empty selection must use clipboard input, not copy a line.
        if let focus, isTextInput(focus), (selectedRange(focus)?.length ?? 0) == 0 {
            return CapturedInput(text: clipboardText ?? "", snapshot: nil, element: nil, window: nil)
        }
        // Read-only browser/PDF selections may live below the focused container.
        if let focus, let selected = findSelection(focus, remaining: 100, depth: 0) {
            return input(text: selected.1, element: selected.0, pid: pid)
        }
        guard copyIsEnabled(pid: pid) else {
            return CapturedInput(text: clipboardText ?? "", snapshot: nil, element: nil, window: nil)
        }
        let clipboard = try ClipboardSnapshot()
        let pasteboard = NSPasteboard.general
        let originalCount = pasteboard.changeCount
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            throw SelectionError.copyUnavailable
        }
        guard sameFocus(pid: pid, original: focus) else { throw SelectionError.contextChanged }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        for _ in 0..<20 {
            if pasteboard.changeCount != originalCount {
                let copiedCount = pasteboard.changeCount
                let text = pasteboard.string(forType: .string)
                let unchanged = sameFocus(pid: pid, original: focus)
                clipboard.restore(ifChangeCount: copiedCount)
                guard unchanged else { throw SelectionError.contextChanged }
                guard let text, !text.isEmpty else { throw SelectionError.copyUnavailable }
                // An unexposed selection is never eligible for a blind paste replacement.
                return CapturedInput(text: text, snapshot: nil, element: nil, window: nil)
            }
            // Finish clipboard restoration even if the outer translation was cancelled.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { continuation.resume() }
            }
        }
        return CapturedInput(text: clipboard.text ?? "", snapshot: nil, element: nil, window: nil)
    }

    func deliver(_ translation: String, to original: CapturedInput, contextWasInterrupted: Bool) -> DeliveryDecision {
        let currentFocus = focusedElement()
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let current = currentFocus.map { snapshot($0, pid: pid) }
        let decision = DeliveryPolicy.decide(original: original.snapshot, current: current,
                                              contextWasInterrupted: contextWasInterrupted)
        if decision == .replaceSelection, let element = original.element,
           let currentFocus, CFEqual(element, currentFocus),
           let oldWindow = original.window, let currentWindow = elementAttribute(currentFocus, kAXWindowAttribute),
           CFEqual(oldWindow, currentWindow), !IsSecureEventInputEnabled(),
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, translation as CFString) == .success {
            return .replaceSelection
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translation, forType: .string)
        return original.snapshot?.isEditable == true ? .clipboardBecauseTargetChanged : .clipboard
    }

    private func input(text: String, element: AXUIElement, pid: pid_t) -> CapturedInput {
        CapturedInput(text: text, snapshot: snapshot(element, pid: pid), element: element,
                      window: elementAttribute(element, kAXWindowAttribute))
    }

    private func snapshot(_ element: AXUIElement, pid: pid_t) -> TextSnapshot {
        let window = elementAttribute(element, kAXWindowAttribute)
        return TextSnapshot(processID: pid, elementID: String(CFHash(element)),
                            windowID: window.map { String(CFHash($0)) }, range: selectedRange(element),
                            selectedText: string(element, kAXSelectedTextAttribute) ?? "",
                            fullText: boundedFullText(element), isEditable: isEditable(element))
    }

    private func focusedElement() -> AXUIElement? {
        elementAttribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)
    }

    private func sameFocus(pid: pid_t, original: AXUIElement?) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        switch (original, focusedElement()) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return CFEqual(lhs, rhs)
        default: return false
        }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func isEditable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue
    }

    private func isTextInput(_ element: AXUIElement) -> Bool {
        isEditable(element) || [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(string(element, kAXRoleAttribute) ?? "")
    }

    private func boundedFullText(_ element: AXUIElement) -> String? {
        guard let text = string(element, kAXValueAttribute), text.utf16.count <= 1_000_000 else { return nil }
        return text
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole
    }

    private func findSelection(_ element: AXUIElement, remaining: Int, depth: Int) -> (AXUIElement, String)? {
        guard remaining > 0, depth < 5, !isSecure(element) else { return nil }
        if let text = string(element, kAXSelectedTextAttribute), !text.isEmpty { return (element, text) }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        var budget = remaining
        for child in children.prefix(20) {
            budget -= 1
            if let result = findSelection(child, remaining: min(budget, 20), depth: depth + 1) { return result }
        }
        return nil
    }

    private func copyIsEnabled(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard let menu = elementAttribute(app, kAXMenuBarAttribute) else { return false }
        func visit(_ element: AXUIElement, depth: Int) -> Bool {
            guard depth < 4 else { return false }
            if string(element, "AXMenuItemCmdChar")?.uppercased() == "C",
               (attribute(element, kAXEnabledAttribute) as? Bool) == true,
               (attribute(element, "AXMenuItemCmdModifiers") as? Int ?? 0) == 0 { return true }
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            return children.prefix(40).contains { visit($0, depth: depth + 1) }
        }
        return visit(menu, depth: 0)
    }
}
