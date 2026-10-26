import Foundation

public enum PreviewLayout {
    public static let edge: CGFloat = 8
    public static let gap: CGFloat = 8

    public static func maximumSize(anchor: CGRect, screen: CGRect) -> CGSize {
        let below = anchor.minY - screen.minY - gap - edge
        let above = screen.maxY - anchor.maxY - gap - edge
        return CGSize(width: max(1, min(380, screen.width - 2 * edge)),
                      height: max(1, min(420, max(below, above), screen.height - 2 * edge)))
    }

    public static func frame(anchor: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let width = min(size.width, max(1, screen.width - 2 * edge))
        let height = min(size.height, max(1, screen.height - 2 * edge))
        let x = min(max(anchor.midX - width / 2, screen.minX + edge), screen.maxX - width - edge)
        let below = anchor.minY - gap - height
        let proposedY = below >= screen.minY + edge ? below : anchor.maxY + gap
        let y = min(max(proposedY, screen.minY + edge), screen.maxY - height - edge)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
