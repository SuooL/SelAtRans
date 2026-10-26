import AppKit

/// Render the app's actual preview view with synthetic examples; never open a desktop window.
/// Run from the repository root:
/// swiftc Sources/FloatingUI/PreviewCardView.swift scripts/render-readme-previews.swift -o /tmp/selatrans-readme-previews
/// /tmp/selatrans-readme-previews
@main
@MainActor
enum ReadmePreviewRenderer {
    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: "docs/assets", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let examples = [
            ("english", "SelAtRans · 中译英", "Could you send me the updated document by tomorrow morning?",
             "已替换选中文字，剪贴板未更改。"),
            ("chinese", "SelAtRans · 英译中", "请在明天上午前把更新后的文档发给我。",
             "译文已放入剪贴板，可以粘贴。")
        ]
        for (direction, title, translation, status) in examples {
            for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                let card = PreviewCardView(frame: .zero)
                let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.isOpaque = false
                window.backgroundColor = .clear
                window.contentView = card
                defer { window.contentView = nil; window.close() }
                card.appearance = NSAppearance(named: appearance)
                card.setTitle(title)
                card.setTranslation(translation)
                card.setStatus(status, canCopy: true)
                card.frame = CGRect(origin: .zero, size: card.preferredSize(maximum: CGSize(width: 380, height: 420)))
                window.setContentSize(card.frame.size)
                card.needsLayout = true
                card.layoutSubtreeIfNeeded()
                guard let bitmap = card.bitmapImageRepForCachingDisplay(in: card.bounds) else {
                    fatalError("Unable to render native preview")
                }
                bitmap.size = card.bounds.size
                card.cacheDisplay(in: card.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    fatalError("Unable to encode native preview")
                }
                let file = output.appendingPathComponent("preview-\(direction)-\(name).png")
                try data.write(to: file)
                print("Rendered \(file.lastPathComponent)")
            }
        }
    }
}
