import AppKit
import TranslationCore

enum IndicatorState {
    case idle, working, success, error, paused
    var color: NSColor {
        switch self {
        case .idle: return .systemTeal
        case .working: return .systemBlue
        case .success: return .systemGreen
        case .error: return .systemOrange
        case .paused: return .secondaryLabelColor
        }
    }
    var symbol: String {
        switch self {
        case .idle: return "character.bubble"
        case .working: return "ellipsis"
        case .success: return "checkmark"
        case .error: return "exclamationmark"
        case .paused: return "pause.fill"
        }
    }
}

final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingIndicator: NSObject {
    private let preferences: Preferences
    private let panel: StatusPanel
    private let indicator = IndicatorView(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
    private var toast: StatusPanel?
    private var previewBody: NSTextView?
    private var previewStatus: NSTextField?
    private var previewTitle: NSTextField?
    private var copyButton: NSButton?
    private var latestTranslation = ""
    private var pendingDelta = ""
    private var refreshTimer: Timer?
    private var translationComplete = false
    private var direction: TranslationDirection = .toEnglish
    private var permissionWarningIsVisible = false
    var onSettings: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onTranslateClipboard: ((TranslationDirection) -> Void)?
    var isPaused = false
    private(set) var message = "就绪 · ⇧⌘E 英文 · ⇧⌘C 中文"

    init(preferences: Preferences) {
        self.preferences = preferences
        panel = StatusPanel(contentRect: NSRect(x: 0, y: 0, width: 48, height: 48),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = indicator
        indicator.onClick = { [weak self] in self?.togglePreview() }
        indicator.onMenu = { [weak self] event in self?.showMenu(event) }
        indicator.onDragFinished = { [weak self] in self?.savePosition() }
        indicator.setAccessibilityElement(true)
        indicator.setAccessibilityRole(.image)
        update(.idle, message: message)
    }

    func show() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let proposed = preferences.indicatorOrigin ?? NSPoint(x: screen.maxX - 72, y: screen.midY)
        let frame = NSRect(origin: proposed, size: panel.frame.size)
        if NSScreen.screens.contains(where: { $0.visibleFrame.contains(frame) }) { panel.setFrameOrigin(proposed) }
        else { panel.setFrameOrigin(NSPoint(x: screen.maxX - 72, y: screen.midY)) }
        panel.orderFrontRegardless()
    }

    func beginTranslation(direction: TranslationDirection) {
        self.direction = direction
        previewTitle?.stringValue = "SelAtRans · " + direction.label
        latestTranslation = ""
        pendingDelta = ""
        translationComplete = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        previewBody?.string = ""
        update(.working, message: "正在翻译 · " + direction.label, showToast: true)
    }

    func appendTranslation(_ delta: String) {
        latestTranslation += delta
        guard toast?.isVisible == true else { return }
        pendingDelta += delta
        guard refreshTimer == nil else { return }
        // Coalesce streaming UI changes to at most ten per second; no idle timer.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPreview() }
        }
    }

    private func flushPreview() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard !pendingDelta.isEmpty else { return }
        let delta = pendingDelta
        pendingDelta = ""
        previewBody?.textStorage?.append(NSAttributedString(string: delta, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor
        ]))
        if let previewBody { previewBody.scrollRangeToVisible(NSRange(location: previewBody.string.utf16.count, length: 0)) }
    }

    func update(_ state: IndicatorState, message: String, showToast: Bool = false, permissionWarning: Bool = false) {
        permissionWarningIsVisible = permissionWarning
        self.message = message
        indicator.state = state
        indicator.toolTip = message + "\n左键查看状态 · 拖动移动 · 右键设置"
        indicator.setAccessibilityLabel("SelAtRans：" + message)
        if state != .working {
            flushPreview()
            if state == .success { translationComplete = !latestTranslation.isEmpty }
            else if state == .error { translationComplete = false }
        }
        previewStatus?.stringValue = message
        copyButton?.isEnabled = translationComplete
        if showToast { showStatus() }
    }

    func synchronizePermission(granted: Bool) {
        guard granted, permissionWarningIsVisible else { return }
        update(isPaused ? .paused : .idle, message: isPaused ? "已授权 · 快捷键已暂停。" : "已授权 · \(preferences.shortcut.label) 英文 · \(preferences.chineseShortcut.label) 中文")
    }

    private func togglePreview() {
        if toast?.isVisible == true { closePreview() } else { showStatus() }
    }

    func showStatus() {
        if let toast, toast.isVisible {
            previewStatus?.stringValue = message
            return
        }
        let width: CGFloat = 380
        let height: CGFloat = 260
        let toast = StatusPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toast.level = .floating
        toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toast.hidesOnDeactivate = false
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.hasShadow = true
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        let title = NSTextField(labelWithString: "SelAtRans · " + direction.label)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: 16, y: height - 30, width: width - 60, height: 14)
        effect.addSubview(title)
        previewTitle = title
        let close = NSButton(title: "×", target: self, action: #selector(closePreview))
        close.isBordered = false
        close.frame = NSRect(x: width - 38, y: height - 36, width: 26, height: 26)
        close.setAccessibilityLabel("收起译文")
        effect.addSubview(close)
        let status = NSTextField(wrappingLabelWithString: message)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: 16, y: 12, width: width - 110, height: 32)
        effect.addSubview(status)
        previewStatus = status
        let copy = NSButton(title: "复制译文", target: self, action: #selector(copyTranslation))
        copy.bezelStyle = .rounded
        copy.frame = NSRect(x: width - 94, y: 15, width: 80, height: 26)
        copy.isEnabled = translationComplete
        effect.addSubview(copy)
        copyButton = copy
        let scroll = NSScrollView(frame: NSRect(x: 16, y: 52, width: width - 32, height: height - 96))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.font = .systemFont(ofSize: 13)
        text.textColor = .labelColor
        text.textContainerInset = NSSize(width: 2, height: 4)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.string = latestTranslation
        pendingDelta = ""
        scroll.documentView = text
        effect.addSubview(scroll)
        previewBody = text
        toast.contentView = effect
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(panel.frame) }?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = min(max(panel.frame.midX - width / 2, screen.minX + 8), screen.maxX - width - 8)
        let below = panel.frame.minY - height - 8
        let y = below >= screen.minY + 8 ? below : min(panel.frame.maxY + 8, screen.maxY - height - 8)
        toast.setFrameOrigin(NSPoint(x: x, y: y))
        toast.orderFrontRegardless()
        self.toast = toast
    }

    @objc private func closePreview() {
        flushPreview()
        toast?.orderOut(nil)
        toast = nil
        previewBody = nil
        previewStatus = nil
        previewTitle = nil
        copyButton = nil
    }

    @objc private func copyTranslation() {
        guard translationComplete else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(latestTranslation, forType: .string)
        previewStatus?.stringValue = "译文已复制。"
    }

    private func savePosition() { preferences.indicatorOrigin = panel.frame.origin }

    private func showMenu(_ event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "SelAtRans · \(preferences.shortcut.label)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        for (title, selector) in [("翻译剪贴板为英文", #selector(clipboardEnglish)), ("翻译剪贴板为中文", #selector(clipboardChinese))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, selector) in [("设置…", #selector(settings)), (isPaused ? "恢复快捷键" : "暂停快捷键", #selector(togglePause)), ("退出 SelAtRans", #selector(quit))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: indicator)
    }
    @objc private func settings() { onSettings?() }
    @objc private func clipboardEnglish() { onTranslateClipboard?(.toEnglish) }
    @objc private func clipboardChinese() { onTranslateClipboard?(.toChinese) }
    @objc private func togglePause() { onTogglePause?() }
    @objc private func quit() { NSApp.terminate(nil) }
}

@MainActor
private final class IndicatorView: NSView {
    var state: IndicatorState = .idle { didSet { needsDisplay = true; updateAnimation() } }
    var onClick: (() -> Void)?
    var onMenu: ((NSEvent) -> Void)?
    var onDragFinished: (() -> Void)?
    private var initialMouse: NSPoint?
    private var initialOrigin: NSPoint?
    private var dragged = false
    private var animation: Timer?
    private var phase: CGFloat = 0

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 15, yRadius: 15)
        NSColor(calibratedWhite: 0.10, alpha: 0.92).setFill()
        background.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        background.lineWidth = 1
        background.stroke()
        let tint = state.color
        if state == .working {
            let path = NSBezierPath()
            path.appendArc(withCenter: NSPoint(x: 24, y: 24), radius: 10,
                           startAngle: phase, endAngle: phase + 270)
            path.lineWidth = 2.3
            path.lineCapStyle = .round
            tint.setStroke()
            path.stroke()
        } else {
            let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
                .applying(.init(paletteColors: [.white]))
            if let image = NSImage(systemSymbolName: state.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                image.isTemplate = false
                image.draw(in: NSRect(x: 13, y: 13, width: 22, height: 22))
                tint.setFill()
                NSBezierPath(ovalIn: NSRect(x: 34, y: 7, width: 5, height: 5)).fill()
            }
        }
    }

    private func updateAnimation() {
        animation?.invalidate()
        animation = nil
        if state == .working {
            animation = Timer.scheduledTimer(withTimeInterval: 1 / 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.phase += 18; self?.needsDisplay = true }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        initialMouse = NSEvent.mouseLocation
        initialOrigin = window?.frame.origin
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let initialMouse, let initialOrigin else { return }
        let current = NSEvent.mouseLocation
        if hypot(current.x - initialMouse.x, current.y - initialMouse.y) > 3 { dragged = true }
        guard dragged, let window else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(current) }?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = min(max(initialOrigin.x + current.x - initialMouse.x, screen.minX), screen.maxX - window.frame.width)
        let y = min(max(initialOrigin.y + current.y - initialMouse.y, screen.minY), screen.maxY - window.frame.height)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { onDragFinished?() } else { onClick?() }
        initialMouse = nil
        initialOrigin = nil
    }
    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
}
