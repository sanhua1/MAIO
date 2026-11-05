import AppKit

/// 「在终端中打开」可选的终端 App（只列出已安装的）
struct TerminalApp: Identifiable, Hashable {
    let bundleID: String
    let name: String

    var id: String {
        bundleID
    }

    static let known: [TerminalApp] = [
        TerminalApp(bundleID: "com.apple.Terminal", name: "终端"),
        TerminalApp(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
        TerminalApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        TerminalApp(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
        TerminalApp(bundleID: "net.kovidgoyal.kitty", name: "kitty"),
        TerminalApp(bundleID: "dev.commandline.waveterm", name: "Wave"),
    ]

    @MainActor static var installed: [TerminalApp] {
        known.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }
}
