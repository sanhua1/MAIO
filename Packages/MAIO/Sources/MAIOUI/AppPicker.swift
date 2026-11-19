import AppKit
import SwiftUI

/// 选一个 App：从运行中的 App 里选，或者选一个 .app（可以进到包里）。
public struct AppPickerMenu: View {
    let title: String
    let panelMessage: String?
    let onPick: (_ bundleID: String, _ name: String) -> Void

    public init(
        _ title: String = "添加 App",
        panelMessage: String? = nil,
        onPick: @escaping (_ bundleID: String, _ name: String) -> Void,
    ) {
        self.title = title
        self.panelMessage = panelMessage
        self.onPick = onPick
    }

    public var body: some View {
        Menu(title) {
            Section("运行中的 App") {
                ForEach(Self.runningApps(), id: \.bundleID) { app in
                    Button(app.name) { onPick(app.bundleID, app.name) }
                }
            }
            Divider()
            Button("选择 App…") { chooseApp() }
        }
        .fixedSize()
    }

    private static func runningApps() -> [(bundleID: String, name: String)] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = URL(filePath: "/Applications")
        if let panelMessage {
            panel.message = panelMessage
        }
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        onPick(id, name)
    }
}

/// App 的图标（16×16）；本机找不到这个 App 时不显示。
public struct AppIconView: View {
    let bundleID: String

    public init(bundleID: String) {
        self.bundleID = bundleID
    }

    public var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 16, height: 16)
        }
    }
}
