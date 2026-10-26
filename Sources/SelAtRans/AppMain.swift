import AppKit
import TranslationCore

@main
struct SelAtRansMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let selection = SelectionService()
    private let hotKey = HotKeyManager(id: 1)
    private let chineseHotKey = HotKeyManager(id: 2)
    private let keychain = KeychainStore()
    private var updater: AppUpdater?
    private lazy var indicator = FloatingIndicator(preferences: preferences)
    private var settings: SettingsWindowController?
    private var translationTask: Task<Void, Never>?
    private var contextGuard: ContextGuard?
    private var paused = false
    private var shortcutRegistered = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        indicator.onSettings = { [weak self] in self?.openSettings() }
        indicator.onTogglePause = { [weak self] in self?.togglePause() }
        hotKey.onFire = { [weak self] in self?.translate(direction: .toEnglish) }
        chineseHotKey.onFire = { [weak self] in self?.translate(direction: .toChinese) }
        indicator.show()
        updater = AppUpdater()
        do { try registerShortcuts() }
        catch { indicator.update(.error, message: error.localizedDescription, showToast: true) }
        if !preferences.hasCompletedSetup { openSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        indicator.show()
        openSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        translationTask?.cancel()
        contextGuard?.stop()
        hotKey.unregister()
        chineseHotKey.unregister()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        indicator.synchronizePermission(granted: selection.isTrusted)
    }

    private func translate(direction: TranslationDirection) {
        guard !paused, translationTask == nil else { return }
        indicator.beginTranslation(direction: direction)
        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { contextGuard?.stop(); contextGuard = nil; translationTask = nil }
            do {
                guard let profile = preferences.profiles.active else { throw TranslationError.missingModel }
                let config = profile.configuration
                try config.validate()
                let key = try keychain.read(account: profile.credentialAccount()) ?? ""
                guard !key.isEmpty else { throw TranslationError.missingKey }
                let input = try await selection.capture()
                try Task.checkCancellation()
                contextGuard = ContextGuard(input: input)
                let translation = try await TranslationClient().translate(input.text, configuration: config, key: key, direction: direction) { [weak self] delta in
                    await MainActor.run { self?.indicator.appendTranslation(delta) }
                }
                try Task.checkCancellation()
                let interrupted = contextGuard?.interrupted ?? false
                contextGuard?.stop()
                let decision = selection.deliver(translation, to: input, contextWasInterrupted: interrupted)
                switch decision {
                case .replaceSelection: indicator.update(.success, message: "已替换选中文字，剪贴板保持不变。", showToast: true)
                case .clipboard: indicator.update(.success, message: "\(direction.target)已放入剪贴板，可以粘贴。", showToast: true)
                case .clipboardBecauseTargetChanged: indicator.update(.success, message: "原选区已变化或无法安全替换，已保留原文并复制译文。", showToast: true)
                }
            } catch is CancellationError {
                indicator.update(.idle, message: "翻译已取消，原文已保留。")
            } catch {
                let needsPermission: Bool
                if let problem = error as? SelectionError, case .permission = problem { needsPermission = true }
                else { needsPermission = false }
                indicator.update(.error, message: error.localizedDescription, showToast: true, permissionWarning: needsPermission)
            }
        }
    }

    private func togglePause() {
        guard translationTask == nil else {
            indicator.showStatus()
            return
        }
        if paused {
            do { try registerShortcuts(); paused = false }
            catch { indicator.update(.error, message: error.localizedDescription, showToast: true); return }
        } else { hotKey.unregister(); chineseHotKey.unregister(); shortcutRegistered = false; paused = true }
        indicator.isPaused = paused
        indicator.update(paused ? .paused : .idle,
                         message: paused ? "快捷键已暂停，右键浮标可恢复。" : "就绪 · \(preferences.shortcut.label) 英文 · \(preferences.chineseShortcut.label) 中文", showToast: true)
    }

    private func openSettings() {
        if settings == nil {
            guard let updater else { return }
            let model = SettingsModel(preferences: preferences, updater: updater)
            model.onShortcut = { [weak self] direction, shortcut in
                guard let self else { return }
                let old = direction == .toEnglish ? preferences.shortcut : preferences.chineseShortcut
                let other = direction == .toEnglish ? preferences.chineseShortcut : preferences.shortcut
                guard shortcut.keyCode != other.keyCode || shortcut.modifiers != other.modifiers else { throw HotKeyError.conflict }
                if !paused, shortcut != old || !shortcutRegistered {
                    do {
                        try registerShortcuts(english: direction == .toEnglish ? shortcut : nil,
                                              chinese: direction == .toChinese ? shortcut : nil)
                    } catch {
                        try? registerShortcuts()
                        throw error
                    }
                }
            }
            model.onSaved = { [weak self] in
                guard let self, translationTask == nil else { return }
                indicator.update(paused ? .paused : .idle, message: paused ? "快捷键已暂停。" : "就绪 · \(preferences.shortcut.label) 英文 · \(preferences.chineseShortcut.label) 中文")
            }
            model.onPermissionChanged = { [weak self] granted in self?.indicator.synchronizePermission(granted: granted) }
            settings = SettingsWindowController(model: model, onPermission: { [weak self] in
                self?.selection.requestPermission()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            })
            settings?.onClose = { [weak self] in
                // Let AppKit finish closing before releasing the SwiftUI view tree.
                DispatchQueue.main.async { self?.settings = nil }
            }
        }
        settings?.present()
    }

    private func registerShortcuts(english: Shortcut? = nil, chinese: Shortcut? = nil) throws {
        do {
            try hotKey.register(english ?? preferences.shortcut)
            try chineseHotKey.register(chinese ?? preferences.chineseShortcut)
            shortcutRegistered = true
        } catch {
            hotKey.unregister(); chineseHotKey.unregister(); shortcutRegistered = false
            throw error
        }
    }
}
