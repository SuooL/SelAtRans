import AppKit
import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isCheckingFeed = false
    @Published private(set) var message = ""
    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }
    func check() {
        guard canCheckForUpdates, !isCheckingFeed else { return }
        isCheckingFeed = true
        message = "正在检查更新源…"
        Task { [weak self] in
            guard let self else { return }
            defer { isCheckingFeed = false }
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            do {
                let url = URL(string: "https://github.com/SuooL/SelAtRans/releases/latest/download/appcast.xml")!
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 15
                let (_, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if response.statusCode == 404 {
                    message = "尚未发布可用的更新版本。首个版本发布后即可检查更新。"
                } else if (200..<300).contains(response.statusCode) {
                    message = ""
                    controller.checkForUpdates(nil)
                } else {
                    message = "更新源暂不可用（HTTP \(response.statusCode)），请稍后重试。"
                }
            } catch { message = "暂时无法连接更新源，请检查网络后重试。" }
        }
    }
}

@MainActor
struct UpdateSettingsView: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("软件更新").font(.headline)
                Text("v\(updater.currentVersion)").foregroundStyle(.secondary)
                Spacer()
                Button(updater.isCheckingFeed ? "检查中…" : "检查更新…") { updater.check() }
                    .disabled(!updater.canCheckForUpdates || updater.isCheckingFeed)
            }
            Toggle("自动检查更新（每天一次）", isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
            Text("通过 GitHub Release 和 Sparkle 签名验证更新，安装前由你确认。")
                .font(.caption).foregroundStyle(.secondary)
            Link("版本记录与下载", destination: URL(string: "https://github.com/SuooL/SelAtRans/releases")!)
            if !updater.message.isEmpty { Text(updater.message).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
