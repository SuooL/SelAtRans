import AppKit
import ApplicationServices

@MainActor
final class ContextGuard {
    private(set) var interrupted = false
    private var eventMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var observer: AXObserver?
    private var watched: [(AXUIElement, String)] = []

    init(input: CapturedInput) {
        guard let snapshot = input.snapshot, snapshot.isEditable, let element = input.element else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.interrupted = true }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            if pid != snapshot.processID { MainActor.assumeIsolated { self?.interrupted = true } }
        }
        var created: AXObserver?
        guard AXObserverCreate(snapshot.processID, { _, _, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<ContextGuard>.fromOpaque(context).takeUnretainedValue().interrupted = true
            }
        }, &created) == .success, let created else { return }
        observer = created
        let app = AXUIElementCreateApplication(snapshot.processID)
        for (target, notification) in [
            (element, kAXSelectedTextChangedNotification), (element, kAXValueChangedNotification),
            (app, kAXFocusedUIElementChangedNotification), (app, kAXFocusedWindowChangedNotification)
        ] {
            if AXObserverAddNotification(created, target, notification as CFString,
                                         Unmanaged.passUnretained(self).toOpaque()) == .success {
                watched.append((target, notification))
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        if let observer {
            for (element, notification) in watched { AXObserverRemoveNotification(observer, element, notification as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        watched.removeAll()
    }
}
