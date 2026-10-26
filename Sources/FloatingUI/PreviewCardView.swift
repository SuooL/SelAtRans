import AppKit

/// Explicit rounded drawing keeps the window's corners transparent in both appearances.
@MainActor
public final class PreviewCardView: NSView {
    public var onClose: (() -> Void)?
    public var onCopy: (() -> Void)?
    private let title = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let close = NSButton(title: "×", target: nil, action: nil)
    private let copy = NSButton(title: "复制译文", target: nil, action: nil)
    private let scroll = NSScrollView()
    private let text = NSTextView()
    private var measuredWidth: CGFloat = 0
    private var textHeight: CGFloat = 0
    private var footerHeight: CGFloat = 26
    private var needsMeasurement = true
    public override var isOpaque: Bool { false }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        close.target = self
        close.action = #selector(closePressed)
        close.isBordered = false
        close.setAccessibilityLabel("收起译文")
        copy.target = self
        copy.action = #selector(copyPressed)
        copy.bezelStyle = .rounded
        copy.isEnabled = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.backgroundColor = .clear
        text.font = .systemFont(ofSize: 13)
        text.textColor = .labelColor
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        for view in [title, status, close, copy, scroll] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func setTitle(_ value: String) { title.stringValue = value }
    public func setStatus(_ value: String, canCopy: Bool) {
        if status.stringValue != value { status.stringValue = value; needsMeasurement = true }
        copy.isEnabled = canCopy
    }
    public func setTranslation(_ value: String) {
        text.string = value
        needsMeasurement = true
    }
    public func appendTranslation(_ value: String) {
        text.textStorage?.append(NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor
        ]))
        needsMeasurement = true
    }
    public func scrollToEnd() {
        text.scrollRangeToVisible(NSRange(location: text.string.utf16.count, length: 0))
    }

    private func measure(width: CGFloat) {
        guard needsMeasurement || width != measuredWidth else { return }
        measuredWidth = width
        let bodyWidth = max(1, width - 32)
        text.setFrameSize(NSSize(width: bodyWidth, height: text.frame.height))
        if let container = text.textContainer, let manager = text.layoutManager {
            container.containerSize = NSSize(width: bodyWidth, height: .greatestFiniteMagnitude)
            manager.ensureLayout(for: container)
            textHeight = text.string.isEmpty ? 0 : ceil(manager.usedRect(for: container).height)
        }
        let statusWidth = max(1, width - 122)
        let statusSize = (status.stringValue as NSString).boundingRect(
            with: NSSize(width: statusWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 11)])
        footerHeight = max(26, ceil(statusSize.height))
        needsMeasurement = false
        needsLayout = true
    }

    public func preferredSize(maximum: CGSize) -> CGSize {
        measure(width: maximum.width)
        let naturalHeight: CGFloat = 16 + 14 + 12 + (textHeight > 0 ? textHeight + 12 : 0) + footerHeight + 12
        return CGSize(width: maximum.width, height: min(naturalHeight, maximum.height))
    }

    public override func layout() {
        super.layout()
        measure(width: bounds.width)
        let width = bounds.width
        title.frame = NSRect(x: 16, y: bounds.height - 30, width: max(1, width - 60), height: 14)
        close.frame = NSRect(x: width - 38, y: bounds.height - 36, width: 26, height: 26)
        status.frame = NSRect(x: 16, y: 12, width: max(1, width - 122), height: footerHeight)
        copy.frame = NSRect(x: width - 94, y: 12 + (footerHeight - 26) / 2, width: 80, height: 26)
        let bodyBottom = 12 + footerHeight + 12
        let bodyTop = bounds.height - 42
        scroll.isHidden = textHeight == 0
        scroll.frame = NSRect(x: 16, y: bodyBottom, width: max(1, width - 32), height: max(0, bodyTop - bodyBottom))
        text.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(textHeight, scroll.contentSize.height)))
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        NSColor.windowBackgroundColor.setFill()
        shape.fill()
        NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }

    @objc private func closePressed() { onClose?() }
    @objc private func copyPressed() { if copy.isEnabled { onCopy?() } }
}
