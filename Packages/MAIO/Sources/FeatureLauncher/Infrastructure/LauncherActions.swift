import AppKit
import UniformTypeIdentifiers

/// 打开结果、在 Finder 中显示。
@MainActor
enum LauncherActions {
    /// 打开 / 执行（应用已经在运行就切到前台）。`perform` 执行 MAIO 命令
    static func open(_ item: LauncherItem, perform: (String) async throws -> Void) async throws {
        switch item.kind {
        case let .app(path, _):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: URL(filePath: path), configuration: configuration)
        case let .file(path, _):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            try await NSWorkspace.shared.open(URL(filePath: path), configuration: configuration)
        case let .web(url):
            NSWorkspace.shared.open(url)
        case let .command(id, _):
            try await perform(id)
        case let .settingsPane(id, _, _):
            guard let url = URL(string: "x-apple.systempreferences:" + id) else { return }
            NSWorkspace.shared.open(url)
        case let .system(action):
            try await SystemActionRunner.run(action)
        }
    }

    /// ⌘C：复制路径；⌘⇧C：复制文件本身（可以在 Finder 里粘贴）
    static func copy(_ item: LauncherItem, asFile: Bool) -> Bool {
        guard let path = item.path else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if asFile {
            return pasteboard.writeObjects([URL(filePath: path) as NSURL])
        }
        return pasteboard.setString(path, forType: .string)
    }

    static func reveal(_ item: LauncherItem) {
        guard let path = item.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }

    /// 正在运行的应用对应的条目 ID（和 `LauncherItem.app` 的 ID 规则一致）
    static func runningAppIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { app in
            if let bundleID = app.bundleIdentifier {
                return "app:" + bundleID
            }
            return app.bundleURL.map { "app:" + $0.path(percentEncoded: false) }
        })
    }
}

/// 图标缓存（同一个路径只向系统要一次）
@MainActor
final class IconCache {
    private var icons: [String: NSImage] = [:]

    func icon(for item: LauncherItem) -> NSImage {
        let key = Self.key(for: item)
        if let cached = icons[key] {
            return cached
        }
        let image = Self.load(item)
        icons[key] = image
        return image
    }

    private static func key(for item: LauncherItem) -> String {
        switch item.kind {
        case let .app(path, _), let .file(path, _): path
        case .web: "web"
        case .command, .system: "symbol"
        case let .settingsPane(_, path, iconType): iconType ?? path
        }
    }

    private static func load(_ item: LauncherItem) -> NSImage {
        switch item.kind {
        case let .app(path, _), let .file(path, _):
            return NSWorkspace.shared.icon(forFile: path)
        case .web:
            return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
        case .command, .system:
            // 行里直接画 SF Symbol，不用这张图
            return NSImage()
        case let .settingsPane(_, path, iconType):
            if let iconType, let type = UTType(iconType) {
                return NSWorkspace.shared.icon(for: type)
            }
            return NSWorkspace.shared.icon(forFile: path)
        }
    }
}
