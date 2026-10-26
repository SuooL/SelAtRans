import Foundation

public struct TextSnapshot: Equatable, Sendable {
    public let processID: Int32
    public let elementID: String
    public let windowID: String?
    public let range: NSRange?
    public let selectedText: String
    public let fullText: String?
    public let isEditable: Bool

    public init(processID: Int32, elementID: String, windowID: String?, range: NSRange?,
                selectedText: String, fullText: String?, isEditable: Bool) {
        self.processID = processID
        self.elementID = elementID
        self.windowID = windowID
        self.range = range
        self.selectedText = selectedText
        self.fullText = fullText
        self.isEditable = isEditable
    }
}

public enum DeliveryDecision: Equatable {
    case replaceSelection
    case clipboard
    case clipboardBecauseTargetChanged
}

public enum DeliveryPolicy {
    public static func decide(original: TextSnapshot?, current: TextSnapshot?,
                              contextWasInterrupted: Bool = false) -> DeliveryDecision {
        guard let original, original.isEditable else { return .clipboard }
        guard !contextWasInterrupted,
              let range = original.range, range.length > 0,
              original.fullText != nil, original.windowID != nil,
              original == current else { return .clipboardBecauseTargetChanged }
        return .replaceSelection
    }
}
