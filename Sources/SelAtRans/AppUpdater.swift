import AppKit
import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
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
    func check() { controller.checkForUpdates(nil) }
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
                Button("检查更新…") { updater.check() }.disabled(!updater.canCheckForUpdates)
            }
            Toggle("自动检查更新（每天一次）", isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
            Text("通过 GitHub Release 和 Sparkle 签名验证更新，安装前由你确认。")
                .font(.caption).foregroundStyle(.secondary)
            Link("版本记录与下载", destination: URL(string: "https://github.com/SuooL/SelAtRans/releases")!)
        }
    }
}
