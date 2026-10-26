import AppKit
import TranslationCore
import FloatingUI

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
    private var previewCard: PreviewCardView?
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
        indicator.onDrag = { [weak self] in self?.layoutPreview() }
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
        layoutPreview()
    }

    func beginTranslation(direction: TranslationDirection) {
        self.direction = direction
        previewCard?.setTitle("SelAtRans · " + direction.label)
        latestTranslation = ""
        pendingDelta = ""
        translationComplete = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        previewCard?.setTranslation("")
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
        previewCard?.appendTranslation(delta)
        layoutPreview()
        previewCard?.scrollToEnd()
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
        previewCard?.setStatus(message, canCopy: translationComplete)
        if showToast { showStatus() } else { layoutPreview() }
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
            previewCard?.setStatus(message, canCopy: translationComplete)
            layoutPreview()
            return
        }
        let toast = StatusPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 80),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toast.level = .floating
        toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toast.hidesOnDeactivate = false
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.hasShadow = true
        let card = PreviewCardView(frame: NSRect(x: 0, y: 0, width: 380, height: 80))
        card.setTitle("SelAtRans · " + direction.label)
        card.setStatus(message, canCopy: translationComplete)
        card.setTranslation(latestTranslation)
        card.onClose = { [weak self] in self?.closePreview() }
        card.onCopy = { [weak self] in self?.copyTranslation() }
        pendingDelta = ""
        toast.contentView = card
        previewCard = card
        self.toast = toast
        layoutPreview()
        toast.orderFrontRegardless()
        card.scrollToEnd()
    }

    private func layoutPreview() {
        guard let toast, let card = previewCard else { return }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return }
        let maximum = PreviewLayout.maximumSize(anchor: panel.frame, screen: screen.visibleFrame)
        let size = card.preferredSize(maximum: maximum)
        let frame = PreviewLayout.frame(anchor: panel.frame, size: size, screen: screen.visibleFrame)
        let resized = toast.frame.size != frame.size
        if toast.frame != frame { toast.setFrame(frame, display: true) }
        if resized {
            card.frame = NSRect(origin: .zero, size: frame.size)
            card.needsLayout = true
        }
        card.layoutSubtreeIfNeeded()
        if resized { toast.invalidateShadow() }
    }

    @objc private func closePreview() {
        flushPreview()
        toast?.orderOut(nil)
        toast = nil
        previewCard = nil
    }

    @objc private func copyTranslation() {
        guard translationComplete else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(latestTranslation, forType: .string)
        previewCard?.setStatus("译文已复制。", canCopy: translationComplete)
        layoutPreview()
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
    var onDrag: (() -> Void)?
    var onDragFinished: (() -> Void)?
    private var initialMouse: NSPoint?
    private var initialOrigin: NSPoint?
    private var dragged = false
    private var animation: Timer?
    private var phase: CGFloat = 0

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
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
        onDrag?()
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { onDragFinished?() } else { onClick?() }
        initialMouse = nil
        initialOrigin = nil
    }
    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
}
