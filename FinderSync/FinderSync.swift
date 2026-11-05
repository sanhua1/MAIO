import Cocoa
import FinderSync

/// 菜单配置：和 `FeatureFinder/Domain/ContextMenu.swift` 的 `ContextMenuConfig` 同一结构（主程序写，这里只读）
private struct MenuConfig: Decodable {
    struct Entry: Decodable {
        var id: String
        var title: String
        var symbol: String?
        var places: [String]
        var children: [Entry]?
    }

    var entries: [Entry]
}

/// Finder 右键菜单扩展（ADR-0019）。扩展必须开沙盒，所以只负责显示菜单；
/// 点击后用 maio:// URL 把动作交给所在的 MAIO（`finder.contextMenu` 命令）执行。
final class FinderSync: FIFinderSync {
    /// Finder 回调时只保留菜单项的 tag，用它找回动作 ID
    private var actions: [Int: String] = [:]

    override init() {
        super.init()
        // 监视整个磁盘，右键菜单才会在所有位置出现
        FIFinderSyncController.default().directoryURLs = [URL(filePath: "/")]
    }

    override func menu(for kind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        let place: String? = switch kind {
        case .contextualMenuForItems: "items"
        case .contextualMenuForContainer: "container"
        default: nil
        }
        guard let place, let config = Self.loadConfig() else { return menu }
        actions = [:]
        for entry in config.entries where entry.places.contains(place) {
            menu.addItem(makeItem(entry))
        }
        return menu
    }

    private func makeItem(_ entry: MenuConfig.Entry) -> NSMenuItem {
        let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
        if let symbol = entry.symbol {
            item.image = Self.menuImage(symbol)
        }
        if let children = entry.children {
            let submenu = NSMenu(title: entry.title)
            children.forEach { submenu.addItem(makeItem($0)) }
            item.submenu = submenu
        } else {
            let tag = actions.count + 1
            actions[tag] = entry.id
            item.tag = tag
            item.action = #selector(run(_:))
            item.target = self
        }
        return item
    }

    @objc private func run(_ sender: NSMenuItem) {
        guard let action = actions[sender.tag] else { return }
        let controller = FIFinderSyncController.default()
        var components = URLComponents()
        components.scheme = "maio"
        components.host = "run"
        components.path = "/finder.contextMenu"
        components.queryItems = [
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "target", value: controller.targetedURL()?.path(percentEncoded: false) ?? ""),
            URLQueryItem(
                name: "items",
                value: (controller.selectedItemURLs() ?? []).map { $0.path(percentEncoded: false) }.joined(separator: "\n"),
            ),
        ]
        guard let url = components.url else { return }
        // 交给扩展所在的那个 MAIO（装了多份时不会发错）；不激活 MAIO，Finder 保持在前台
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open([url], withApplicationAt: Self.containingApp, configuration: configuration)
    }

    /// 菜单图标：菜单项交给 Finder 时图片的"模板"属性会丢，Finder 按原色（黑色）画，深色模式下看不清。
    /// 所以按当前外观把符号预先画成菜单文字的颜色（每次右键都重新生成菜单，切换深浅色后也对）
    private static func menuImage(_ symbol: String) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)) else { return nil }
        let size = base.size
        let scale = 2.0
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0,
        ) else { return base }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        systemAppearance.performAsCurrentDrawingAppearance {
            let rect = NSRect(origin: .zero, size: size)
            base.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    /// 系统当前是深色还是浅色（全局配置里的 AppleInterfaceStyle；"自动"模式下也会跟着当前状态变）
    private static var systemAppearance: NSAppearance {
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String
        return NSAppearance(named: style == "Dark" ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
    }

    /// MAIO.app/Contents/PlugIns/MAIOFinderSync.appex → MAIO.app
    private static var containingApp: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 沙盒里 home 目录指向容器，要用真实的用户目录（entitlements 里给了这个文件夹的只读例外）
    private static func loadConfig() -> MenuConfig? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        let file = URL(filePath: String(cString: home))
            .appending(path: "Library/Application Support/MAIO/data/finder/context-menu.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(MenuConfig.self, from: data)
    }
}
