import AppKit
import SwiftUI
import TranslationCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published var collection: ProfileCollection
    @Published var selectedID: UUID?
    @Published var name = ""
    @Published var baseURL = ""
    @Published var model = ""
    @Published var effort: ReasoningEffort = .providerDefault
    @Published var key = ""
    @Published var hasSavedKey = false
    @Published var message = ""
    @Published var isTesting = false
    @Published var isRecording = false
    @Published var shortcutLabel: String
    @Published var chineseShortcutLabel: String
    @Published var recordingDirection: TranslationDirection?
    @Published var hasPermission = false
    let updater: AppUpdater
    var onShortcut: ((TranslationDirection, Shortcut) throws -> Void)?
    var onSaved: (() -> Void)?
    var onPermissionChanged: ((Bool) -> Void)?
    private let preferences: Preferences
    private let keychain = KeychainStore()
    private var recorder: Any?
    private var testTask: Task<Void, Never>?

    init(preferences: Preferences, updater: AppUpdater) {
        self.preferences = preferences
        self.updater = updater
        collection = preferences.profiles
        shortcutLabel = preferences.shortcut.label
        chineseShortcutLabel = preferences.chineseShortcut.label
        select(collection.activeID ?? collection.profiles.first?.id)
    }

    var configuration: APIConfiguration {
        .init(baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
              model: model.trimmingCharacters(in: .whitespacesAndNewlines), effort: effort)
    }
    private var editedProfile: LLMProfile? {
        guard let id = selectedID else { return nil }
        return LLMProfile(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), configuration: configuration)
    }

    func refresh() {
        hasPermission = AXIsProcessTrusted()
        onPermissionChanged?(hasPermission)
        if let profile = editedProfile, let account = try? profile.credentialAccount() {
            hasSavedKey = (try? keychain.read(account: account)) != nil
        } else { hasSavedKey = false }
    }

    func select(_ id: UUID?) {
        guard !isTesting else { return }
        selectedID = id
        key = ""
        message = ""
        if let profile = collection.profiles.first(where: { $0.id == id }) {
            name = profile.name
            baseURL = profile.configuration.baseURL
            model = profile.configuration.model
            effort = profile.configuration.effort
        }
        refresh()
    }

    func endpointChanged() {
        key = ""
        if !ReasoningEffort.supported(for: baseURL).contains(effort) { effort = .providerDefault }
        refresh()
    }

    func addProfile() {
        guard !isTesting else { return }
        let profile = LLMProfile(name: "新配置")
        collection.profiles.append(profile)
        preferences.profiles = collection
        select(profile.id)
    }

    func deleteProfile() {
        guard !isTesting, let id = selectedID else { return }
        do {
            try keychain.deleteProfile(id: id)
            collection.remove(id: id)
            preferences.profiles = collection
            select(collection.profiles.first?.id)
            message = "已删除配置及其密钥。"
            onSaved?()
        } catch { message = error.localizedDescription }
    }

    @discardableResult func save() -> Bool {
        guard let profile = editedProfile else { return false }
        do {
            guard !profile.name.isEmpty else { message = "请填写配置名称。"; return false }
            try profile.configuration.validate()
            if !key.isEmpty {
                let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedKey.isEmpty else { throw TranslationError.missingKey }
                try keychain.save(trimmedKey, account: profile.credentialAccount())
            }
            guard let index = collection.profiles.firstIndex(where: { $0.id == profile.id }) else { return false }
            collection.profiles[index] = profile
            preferences.profiles = collection
            preferences.hasCompletedSetup = true
            key = ""
            refresh()
            message = "配置已保存。密钥仅存于 macOS 钥匙串。"
            onSaved?()
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func activateSelected() {
        guard save(), let profile = editedProfile else { return }
        do {
            guard let saved = try keychain.read(account: profile.credentialAccount()), !saved.isEmpty else { throw TranslationError.missingKey }
            collection.activeID = profile.id
            preferences.profiles = collection
            message = "已启用：\(profile.name)"
            onSaved?()
        } catch { message = error.localizedDescription }
    }

    func deleteKey() {
        guard let profile = editedProfile else { return }
        do {
            try keychain.delete(account: profile.credentialAccount())
            key = ""
            refresh()
            message = "已删除当前配置、当前服务地址的密钥。"
        } catch { message = error.localizedDescription }
    }

    func testConnection() {
        guard !isTesting, let profile = editedProfile else { return }
        isTesting = true
        message = "正在测试，仅发送固定测试句…"
        let typedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        testTask = Task { [weak self] in
            guard let self else { return }
            defer { isTesting = false; testTask = nil }
            do {
                let selectedKey = try typedKey.isEmpty ? keychain.read(account: profile.credentialAccount()) ?? "" : typedKey
                _ = try await TranslationClient().translate("你好，祝你今天愉快。", configuration: profile.configuration, key: selectedKey)
                try Task.checkCancellation()
                message = "连接成功，模型已返回完整译文。测试不会自动保存设置。"
            } catch is CancellationError { message = "测试已取消。" }
            catch { message = error.localizedDescription }
        }
    }

    func recordShortcut(direction: TranslationDirection) {
        if isRecording { stopRecording(); return }
        isRecording = true
        recordingDirection = direction
        message = "请按新的快捷键（包含 ⌘、⌥ 或 ⌃），Esc 取消。"
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleShortcut(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { stopRecording(); return true }
        guard let shortcut = Shortcut(event: event) else { return true }
        do {
            guard let direction = recordingDirection else { return true }
            try onShortcut?(direction, shortcut)
            if direction == .toEnglish { preferences.shortcut = shortcut; shortcutLabel = shortcut.label }
            else { preferences.chineseShortcut = shortcut; chineseShortcutLabel = shortcut.label }
            message = "快捷键已更新。"
        } catch { message = error.localizedDescription }
        stopRecording()
        return true
    }

    func close() { stopRecording(); testTask?.cancel(); key = "" }
    private func stopRecording() {
        if let recorder { NSEvent.removeMonitor(recorder) }
        recorder = nil
        isRecording = false
        recordingDirection = nil
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var onPermission: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "character.bubble.fill").font(.system(size: 28)).foregroundStyle(.teal)
                    .frame(width: 52, height: 52).background(.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("SelAtRans").font(.system(size: 23, weight: .semibold))
                    Text("选中文字，一键变成自然英文。").foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.shortcutLabel).font(.system(.title3, design: .monospaced))
            }
            TabView {
                profiles.tabItem { Label("翻译配置", systemImage: "slider.horizontal.3") }
                general.tabItem { Label("快捷键与更新", systemImage: "gearshape") }
            }
            Text(model.message.isEmpty ? "选择配置，保存后启用即可。" : model.message)
                .font(.callout).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Text("仅在触发时发送文字 · 无翻译历史 · 密钥仅存于钥匙串").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 840)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        .onAppear { model.refresh() }
        .onChange(of: model.baseURL) { _ in model.endpointChanged() }
        .alert("删除这个 LLM 配置？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除配置与密钥", role: .destructive) { model.deleteProfile() }
        } message: { Text("会删除此配置及其钥匙串密钥，不影响其他配置。") }
    }

    private var profiles: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("LLM 配置").font(.headline); Spacer(); Button { model.addProfile() } label: { Image(systemName: "plus") }.disabled(model.isTesting) }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.collection.profiles) { profile in
                            Button { model.select(profile.id) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(profile.name).fontWeight(.medium).lineLimit(1)
                                        Spacer()
                                        if profile.id == model.collection.activeID { Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal) }
                                    }
                                    Text(profile.configuration.model).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Text("effort: \(profile.configuration.effort.label)").font(.caption2).foregroundStyle(.secondary)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(model.selectedID == profile.id ? Color.teal.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).disabled(model.isTesting)
                        }
                    }
                }
                if model.collection.profiles.isEmpty { Text("点击 + 添加配置。").foregroundStyle(.secondary) }
                Spacer()
                if let active = model.collection.active { Text("启用：\(active.name)").font(.caption).foregroundStyle(.secondary) }
                else { Text("尚未启用任何配置").font(.caption).foregroundStyle(.orange) }
            }.frame(width: 200)
            Divider()
            if model.selectedID != nil {
                VStack(alignment: .leading, spacing: 14) {
                    field("名称") { TextField("例如 DeepSeek 日常翻译", text: $model.name) }
                    field("API 地址") { TextField("https://api.deepseek.com", text: $model.baseURL) }
                    field("模型") { TextField("模型 ID", text: $model.model) }
                    field("Effort") {
                        Picker("", selection: $model.effort) {
                            ForEach(ReasoningEffort.supported(for: model.baseURL), id: \.self) { Text($0.label).tag($0) }
                        }.labelsHidden()
                    }
                    Text("服务默认不发送 effort；none 关闭思考。可用等级取决于服务及模型。")
                        .font(.caption).foregroundStyle(.secondary)
                    field("API Key") { SecureField(model.hasSavedKey ? "已保存；留空保持不变" : "输入此配置的密钥", text: $model.key) }
                    HStack {
                        Label(model.hasSavedKey ? "此配置的密钥已保存" : "密钥按配置和服务地址隔离", systemImage: "lock.shield")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if model.hasSavedKey { Button("删除密钥", role: .destructive) { model.deleteKey() }.font(.caption) }
                    }
                    Spacer()
                    HStack {
                        Button("删除配置", role: .destructive) { confirmDelete = true }
                        Spacer()
                        Button(model.isTesting ? "测试中…" : "测试连接") { model.testConnection() }
                        Button("保存") { model.save() }
                        Button("保存并启用") { model.activateSelected() }.buttonStyle(.borderedProminent)
                    }
                }.textFieldStyle(.roundedBorder).disabled(model.isTesting)
            } else {
                VStack { Spacer(); Text("添加或选择一个 LLM 配置").foregroundStyle(.secondary); Spacer() }.frame(maxWidth: .infinity)
            }
        }.padding(16).frame(height: 350)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("中译英快捷键").font(.headline)
                    Text("浮标左键仅查看状态，右键打开设置。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.shortcutLabel).font(.system(.title3, design: .monospaced))
                Button(model.recordingDirection == .toEnglish ? "取消" : "修改…") { model.recordShortcut(direction: .toEnglish) }
            }
            HStack {
                Text("英译中快捷键").font(.headline)
                Spacer()
                Text(model.chineseShortcutLabel).font(.system(.title3, design: .monospaced))
                Button(model.recordingDirection == .toChinese ? "取消" : "修改…") { model.recordShortcut(direction: .toChinese) }
            }
            Divider()
            HStack {
                Label(model.hasPermission ? "辅助功能已允许" : "需要辅助功能权限", systemImage: model.hasPermission ? "checkmark.shield" : "hand.raised")
                Spacer()
                Button("刷新") { model.refresh() }
                Button("前往授权…", action: onPermission)
            }
            if !model.hasPermission {
                Text("授权后返回此窗口会自动刷新。请确认系统设置中添加的是当前版本：\(Bundle.main.bundlePath)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Divider()
            UpdateSettingsView(updater: model.updater)
            Spacer()
            Text("输入框选区直接替换，剪贴板不变；其他位置的文字翻译后复制到剪贴板。若翻译期间原窗口或选区变化，将保留原文并复制译文。")
                .font(.callout).foregroundStyle(.secondary)
        }.padding(18).frame(height: 350)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title).frame(width: 62, alignment: .leading); content() }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel
    var onClose: (() -> Void)?
    init(model: SettingsModel, onPermission: @escaping () -> Void) {
        self.model = model
        let view = NSHostingView(rootView: SettingsView(model: model, onPermission: onPermission))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "SelAtRans 设置"
        window.contentView = view
        window.setContentSize(view.fittingSize)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present() { model.refresh(); showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    func windowWillClose(_ notification: Notification) { model.close(); onClose?() }
}
