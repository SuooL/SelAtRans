import Foundation

public enum CopyAvailability: Equatable { case enabled, disabled, unknown }
public enum SelectionCaptureRoute: Equatable { case clipboard, copySelection, unavailable }

public enum SelectionCapturePolicy {
    /// Missing AX metadata does not prove the absence of a selection.
    public static func route(range: NSRange?, isTextInput: Bool, copy: CopyAvailability,
                             selectionReported: Bool = false) -> SelectionCaptureRoute {
        if selectionReported || (range?.length ?? 0) > 0 {
            return copy == .enabled ? .copySelection : .unavailable
        }
        if isTextInput, range?.length == 0 { return .clipboard }
        switch copy {
        case .enabled: return .copySelection
        case .disabled: return .clipboard
        case .unknown: return .unavailable
        }
    }

    public static func copiedSelection(_ text: String?, clipboardChanged: Bool) -> String? {
        guard clipboardChanged, let text, !text.isEmpty else { return nil }
        return text
    }

    /// Accessibility text ranges are UTF-16, including surrogate pairs and emoji.
    public static func text(in fullText: String, range: NSRange) -> String? {
        let value = fullText as NSString
        guard range.location >= 0, range.length > 0, range.location <= value.length,
              range.length <= value.length - range.location else { return nil }
        func splitsSurrogate(at index: Int) -> Bool {
            index > 0 && index < value.length && value.character(at: index) & 0xfc00 == 0xdc00
                && value.character(at: index - 1) & 0xfc00 == 0xd800
        }
        guard !splitsSurrogate(at: range.location), !splitsSurrogate(at: range.location + range.length) else { return nil }
        return value.substring(with: range)
    }
}
