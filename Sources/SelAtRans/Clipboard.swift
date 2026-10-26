import AppKit

@MainActor
struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard = .general) throws {
        let sourceItems = pasteboard.pasteboardItems ?? []
        // Avoid materializing large image/file clipboard payloads for a selection probe.
        let heavyTypes: Set<NSPasteboard.PasteboardType> = [.tiff, .png, .fileURL, .pdf]
        guard !sourceItems.contains(where: { !Set($0.types).isDisjoint(with: heavyTypes) }) else {
            throw SelectionError.copyUnavailable
        }
        var totalBytes = 0
        items = try sourceItems.map { item in
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    totalBytes += data.count
                    guard totalBytes <= 4 * 1_024 * 1_024 else { throw SelectionError.copyUnavailable }
                    representations[type] = data
                }
            }
            return representations
        }
    }

    func restore(ifChangeCount expected: Int, to pasteboard: NSPasteboard = .general) {
        guard pasteboard.changeCount == expected else { return }
        pasteboard.clearContents()
        let restored = items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
