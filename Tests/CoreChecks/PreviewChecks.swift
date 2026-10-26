import AppKit
import FloatingUI

@MainActor
func runPreviewChecks() throws {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let anchor = CGRect(x: 600, y: 500, width: 48, height: 48)
    let size = CGSize(width: 380, height: 110)
    let initial = PreviewLayout.frame(anchor: anchor, size: size, screen: screen)
    let moved = PreviewLayout.frame(anchor: anchor.offsetBy(dx: 80, dy: 40), size: size, screen: screen)
    precondition(moved == initial.offsetBy(dx: 80, dy: 40))
    precondition(initial.maxY == anchor.minY - PreviewLayout.gap)
    let low = CGRect(x: 600, y: 8, width: 48, height: 48)
    precondition(PreviewLayout.frame(anchor: low, size: size, screen: screen).minY == low.maxY + PreviewLayout.gap)
    // The active screen can have a negative origin, a small viewport, or a narrow width.
    for screen in [screen, CGRect(x: -1000, y: -200, width: 1000, height: 700), CGRect(x: 0, y: 0, width: 300, height: 250)] {
        for point in [CGPoint(x: screen.minX, y: screen.minY), CGPoint(x: screen.midX, y: screen.midY),
                      CGPoint(x: screen.maxX - 48, y: screen.maxY - 48)] {
            let icon = CGRect(origin: point, size: CGSize(width: 48, height: 48))
            let maximum = PreviewLayout.maximumSize(anchor: icon, screen: screen)
            let frame = PreviewLayout.frame(anchor: icon, size: maximum, screen: screen)
            precondition(screen.insetBy(dx: 8, dy: 8).contains(frame))
            precondition(maximum.height <= 420)
            precondition(!icon.intersects(frame))
        }
    }

    _ = NSApplication.shared
    let view = PreviewCardView(frame: CGRect(origin: .zero, size: size))
    view.setTitle("SelAtRans · 中译英")
    view.setStatus("已替换选中文字，剪贴板保持不变。", canCopy: false)
    let maximum = CGSize(width: 380, height: 420)
    let empty = view.preferredSize(maximum: maximum)
    precondition(empty.height < 110)
    view.setTranslation("A short, natural translation.")
    let short = view.preferredSize(maximum: maximum)
    precondition(short.height > empty.height && short.height < 150)
    view.appendTranslation(String(repeating: "\nStreaming output grows naturally with the content. 中文和 emoji 🌍。", count: 60))
    let long = view.preferredSize(maximum: maximum)
    precondition(long.height == maximum.height)
    view.setTranslation("")
    precondition(view.preferredSize(maximum: maximum) == empty)
    view.setTranslation("A short, natural translation.")
    view.setStatus("已复制。", canCopy: true)
    let brief = view.preferredSize(maximum: maximum)
    view.setStatus(String(repeating: "这是较长的状态提示，必须完整显示。", count: 4), canCopy: true)
    precondition(view.preferredSize(maximum: maximum).height > brief.height)

    let render = CommandLine.arguments.contains("--render-preview-checks")
    let output = URL(fileURLWithPath: "build/preview-checks", isDirectory: true)
    if render { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
    for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        let window = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        view.appearance = NSAppearance(named: appearance)
        view.setTranslation("A short, natural translation.")
        view.setStatus("译文已放入剪贴板，可以粘贴。", canCopy: true)
        view.frame = CGRect(origin: .zero, size: view.preferredSize(maximum: maximum))
        window.setContentSize(view.frame.size)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No preview bitmap") }
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        for point in [(1, 1), (bitmap.pixelsWide - 2, 1), (1, bitmap.pixelsHigh - 2), (bitmap.pixelsWide - 2, bitmap.pixelsHigh - 2)] {
            precondition((bitmap.colorAt(x: point.0, y: point.1)?.alphaComponent ?? 1) < 0.01,
                         "Preview corners must be transparent, not a white rectangular backing")
        }
        precondition((bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.alphaComponent ?? 0) > 0.95)
        if render, let data = bitmap.representation(using: .png, properties: [:]) {
            try data.write(to: output.appendingPathComponent("short-" + name + ".png"))
        }
        if let frameView = view.superview, let frameBitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
            frameView.cacheDisplay(in: frameView.bounds, to: frameBitmap)
            precondition((frameBitmap.colorAt(x: 1, y: 1)?.alphaComponent ?? 1) < 0.01,
                         "The nonopaque window frame must not add a white corner backing")
        } else { fatalError("No window frame bitmap") }
    }
    if render {
        view.setTranslation(String(repeating: "Streaming output grows with the translation. 流式输出随内容增长。🌍\n", count: 30))
        view.frame = CGRect(origin: .zero, size: view.preferredSize(maximum: maximum))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("long-dark.png"))
        }
    }
    print("PASS: preview follows anchor, stays on screen, fits content, caps long output, and has transparent corners in light/dark appearances")
}
