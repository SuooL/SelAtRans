import AppKit

let directory = "build/AppIcon.iconset"
let appPath = CommandLine.arguments.dropFirst().first ?? "build/package/SelAtRans.app"
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let inset = CGFloat(pixels) * 0.08
        let background = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                                      xRadius: CGFloat(pixels) * 0.22, yRadius: CGFloat(pixels) * 0.22)
        NSGradient(starting: NSColor(calibratedRed: 0.04, green: 0.55, blue: 0.60, alpha: 1),
                   ending: NSColor(calibratedRed: 0.03, green: 0.26, blue: 0.38, alpha: 1))!.draw(in: background, angle: -70)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: CGFloat(pixels) * 0.34, weight: .semibold), .foregroundColor: NSColor.white]
        let text = "EN" as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (CGFloat(pixels) - textSize.width) / 2, y: (CGFloat(pixels) - textSize.height) / 2), withAttributes: attributes)
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", directory, "-o", "\(appPath)/Contents/Resources/AppIcon.icns"]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("Icon generation failed") }
