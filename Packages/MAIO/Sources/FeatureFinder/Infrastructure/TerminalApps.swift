import AppKit
import UniformTypeIdentifiers

/// 「在终端中打开」可选的终端 App。启动方式是"用这个 App 打开文件夹"，所以任何声明能打开文件夹的 App 都能用
/// （Otty、Ghostty、iTerm2 等都支持）。不在内置列表里的可以在设置里"选择其他 App…"。
struct TerminalApp: Identifiable, Hashable {
    let bundleID: String
    let name: String

    var id: String {
        bundleID
    }

    static let known: [TerminalApp] = [
        TerminalApp(bundleID: "com.apple.Terminal", name: "终端"),
        TerminalApp(bundleID: "io.appmakes.otty", name: "Otty"),
        TerminalApp(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
        TerminalApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        TerminalApp(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
        TerminalApp(bundleID: "net.kovidgoyal.kitty", name: "kitty"),
        TerminalApp(bundleID: "com.github.wez.wezterm", name: "WezTerm"),
        TerminalApp(bundleID: "org.tabby", name: "Tabby"),
        TerminalApp(bundleID: "co.zeit.hyper", name: "Hyper"),
        TerminalApp(bundleID: "dev.commandline.waveterm", name: "Wave"),
    ]

    @MainActor static var installed: [TerminalApp] {
        known.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    /// 已安装列表 + 当前选中的（不在内置列表里的自选 App，或已被卸载的），保证选择器里总有当前值
    @MainActor static func choices(selected bundleID: String) -> [TerminalApp] {
        let list = installed
        guard !list.contains(where: { $0.bundleID == bundleID }) else { return list }
        return list + [TerminalApp(bundleID: bundleID, name: displayName(of: bundleID) ?? bundleID)]
    }

    @MainActor static func displayName(of bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            FileManager.default.displayName(atPath: $0.path(percentEncoded: false))
                .replacingOccurrences(of: ".app", with: "")
        }
    }

    /// 让用户从「应用程序」里选一个 App，返回它的 bundle ID；取消时返回 nil
    @MainActor static func chooseOther() -> String? {
        let panel = NSOpenPanel()
        panel.title = "选择终端 App"
        panel.prompt = "选择"
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
