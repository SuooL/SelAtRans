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
        case .copyUnavailable: return "无法确认当前选区，未使用旧剪贴板。请手动复制，再从浮标右键选择翻译剪贴板。"
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

    func captureClipboard() -> CapturedInput {
        CapturedInput(text: NSPasteboard.general.string(forType: .string) ?? "", snapshot: nil, element: nil, window: nil)
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

        // Search the focused subtree before treating an empty container range as no selection.
        var budget = 100
        var selectionReported = false
        if let focus, let selected = findSelection(focus, budget: &budget, depth: 0, selectionReported: &selectionReported) {
            return try input(text: selected.1, element: selected.0, pid: pid)
        }
        let route = SelectionCapturePolicy.route(range: focus.flatMap(selectedRange),
                                                 isTextInput: focus.map(isTextInput) ?? false,
                                                 copy: copyAvailability(pid: pid), selectionReported: selectionReported)
        switch route {
        case .clipboard: return captureClipboard()
        case .unavailable: throw SelectionError.copyUnavailable
        case .copySelection: break
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
                guard let text = SelectionCapturePolicy.copiedSelection(text, clipboardChanged: true) else {
                    throw SelectionError.copyUnavailable
                }
                // An unexposed selection is never eligible for a blind paste replacement.
                return CapturedInput(text: text, snapshot: nil, element: nil, window: nil)
            }
            // Finish clipboard restoration even if the outer translation was cancelled.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { continuation.resume() }
            }
        }
        // A failed selection probe must never send unrelated clipboard contents.
        throw SelectionError.copyUnavailable
    }

    func deliver(_ translation: String, to original: CapturedInput, contextWasInterrupted: Bool) -> DeliveryDecision {
        if original.snapshot == nil {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(translation, forType: .string)
            return .clipboard
        }
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

    private func input(text: String, element: AXUIElement, pid: pid_t) throws -> CapturedInput {
        let captured = snapshot(element, pid: pid)
        guard captured.selectedText == text else { throw SelectionError.contextChanged }
        return CapturedInput(text: text, snapshot: captured, element: element,
                             window: elementAttribute(element, kAXWindowAttribute))
    }

    private func snapshot(_ element: AXUIElement, pid: pid_t) -> TextSnapshot {
        let window = elementAttribute(element, kAXWindowAttribute)
        return TextSnapshot(processID: pid, elementID: String(CFHash(element)),
                            windowID: window.map { String(CFHash($0)) }, range: selectedRange(element),
                            selectedText: selectedText(element) ?? "",
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

    private func selectedText(_ element: AXUIElement) -> String? {
        if let text = string(element, kAXSelectedTextAttribute), !text.isEmpty { return text }
        guard let range = selectedRange(element), range.length > 0, range.length <= 30_000 else { return nil }
        var cfRange = CFRange(location: range.location, length: range.length)
        if let parameter = AXValueCreate(.cfRange, &cfRange) {
            var value: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                          parameter, &value) == .success,
               let text = value as? String, !text.isEmpty { return text }
        }
        guard let full = boundedFullText(element) else { return nil }
        return SelectionCapturePolicy.text(in: full, range: range)
    }

    private func findSelection(_ element: AXUIElement, budget: inout Int, depth: Int,
                               selectionReported: inout Bool) -> (AXUIElement, String)? {
        guard budget > 0, depth < 7, !isSecure(element) else { return nil }
        budget -= 1
        if let range = selectedRange(element), range.length > 0 { selectionReported = true }
        if let text = selectedText(element) { return (element, text) }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children.prefix(20) {
            if let result = findSelection(child, budget: &budget, depth: depth + 1, selectionReported: &selectionReported) { return result }
            if budget == 0 { break }
        }
        return nil
    }

    private func copyAvailability(pid: pid_t) -> CopyAvailability {
        let app = AXUIElementCreateApplication(pid)
        guard let menu = elementAttribute(app, kAXMenuBarAttribute) else { return .unknown }
        var budget = 200
        var foundDisabled = false
        var foundUnknown = false
        func visit(_ element: AXUIElement, depth: Int) -> Bool {
            guard depth < 6, budget > 0 else { return false }
            budget -= 1
            if string(element, "AXMenuItemCmdChar")?.uppercased() == "C",
               (attribute(element, "AXMenuItemCmdModifiers") as? Int) == 0 {
                if let enabled = attribute(element, kAXEnabledAttribute) as? Bool {
                    if enabled { return true }
                    foundDisabled = true
                } else { foundUnknown = true }
            }
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            return children.prefix(40).contains { visit($0, depth: depth + 1) }
        }
        if visit(menu, depth: 0) { return .enabled }
        return foundDisabled && !foundUnknown && budget > 0 ? .disabled : .unknown
    }
}
