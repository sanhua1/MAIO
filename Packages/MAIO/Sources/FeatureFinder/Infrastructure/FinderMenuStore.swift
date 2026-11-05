import AppKit
import ApplicationServices
import MAIOKit
import Observation

/// Finder 菜单的快照和原生快捷键的修改（NSUserKeyEquivalents，系统设置 › 键盘 › App 快捷键用的同一份配置）。
/// 快照通过辅助功能接口读取，读到的就是 Finder 当前真正生效的快捷键（包括用户改过的）。
@MainActor
@Observable
final class FinderMenuStore {
    private(set) var items: [FinderMenuItem] = []
    /// Finder 配置里的 App 快捷键：菜单路径 → 快捷键（重启 Finder 后生效）
    private(set) var overrides: [[String]: KeyChord] = [:]
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false

    static let key = "NSUserKeyEquivalents"

    /// 重新读取菜单和 App 快捷键
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        overrides = Self.readOverrides()
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: FinderKeymap.bundleID).first?
            .processIdentifier else { return }
        let read = await Task.detached(priority: .utility) { FinderMenuReader.read(pid: pid) }.value
        if !read.isEmpty {
            items = read
            lastRefresh = Date()
        }
    }

    /// 距上次读取超过 `interval` 才读
    func refreshIfStale(_ interval: TimeInterval = 30) async {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < interval {
            return
        }
        await refresh()
    }

    /// 改一个菜单项的快捷键；nil 表示恢复 Finder 默认（删除这一条）
    func setShortcut(_ chord: KeyChord?, for path: [String]) {
        var raw = Self.readRaw()
        // 用户在系统设置里只写了标题的旧条目也一并去掉，避免两条打架
        raw[path.last ?? ""] = nil
        raw[MenuShortcuts.preferenceKey(path)] = chord.flatMap(MenuShortcuts.encode)
        FinderPreferences.writeObject(raw.isEmpty ? nil : raw as CFDictionary, key: Self.key)
        overrides = Self.readOverrides()
    }

    /// 菜单快照，已经套上还没重启生效的修改（用于冲突检测）
    var effectiveItems: [FinderMenuItem] {
        items.map { item in
            override(for: item.path).map { FinderMenuItem(path: item.path, chord: $0, isGlobe: false) } ?? item
        }
    }

    /// 某个菜单项是否被改过（MAIO 或系统设置）
    func override(for path: [String]) -> KeyChord? {
        overrides[path] ?? overrides[[path.last ?? ""]]
    }

    private static func readRaw() -> [String: String] {
        FinderPreferences.object(key: key) as? [String: String] ?? [:]
    }

    private static func readOverrides() -> [[String]: KeyChord] {
        var result: [[String]: KeyChord] = [:]
        for (key, value) in readRaw() {
            if let chord = MenuShortcuts.decode(value) {
                result[MenuShortcuts.path(fromPreferenceKey: key)] = chord
            }
        }
        return result
    }
}

/// 在后台线程用辅助功能接口遍历 Finder 的菜单栏
enum FinderMenuReader {
    /// 这些子菜单的内容随使用情况变化（最近使用的文件夹、服务、窗口列表），不列出来
    static let skippedSubmenus: Set<String> = ["服务", "Services", "最近使用的文件夹", "Recent Folders"]

    static func read(pid: pid_t) -> [FinderMenuItem] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let bar = element(app, kAXMenuBarAttribute) else { return [] }
        // 第一个是苹果菜单，不属于 Finder
        let menus = children(bar).dropFirst()
        var items: [FinderMenuItem] = []
        for menu in menus {
            let title = string(menu, kAXTitleAttribute)
            for list in children(menu) {
                walk(list, path: [title], into: &items)
            }
        }
        return items
    }

    private static func walk(_ menu: AXUIElement, path: [String], into items: inout [FinderMenuItem]) {
        for item in children(menu) {
            let title = string(item, kAXTitleAttribute)
            // 分隔线没有标题；带引号的是随选中项变化的标题（压缩"xxx"）
            guard !title.isEmpty, !title.contains("“"), !title.contains("\"") else { continue }
            let submenus = children(item)
            if !submenus.isEmpty {
                guard !skippedSubmenus.contains(title) else { continue }
                for submenu in submenus {
                    walk(submenu, path: path + [title], into: &items)
                }
                continue
            }
            let shortcut = MenuShortcuts.chord(
                character: string(item, kAXMenuItemCmdCharAttribute),
                modifiers: integer(item, kAXMenuItemCmdModifiersAttribute) ?? 0,
                virtualKey: integer(item, kAXMenuItemCmdVirtualKeyAttribute),
            )
            // "窗口"菜单下面是窗口列表，只保留有快捷键的
            if path.first == "窗口" || path.first == "Window", shortcut == nil {
                continue
            }
            let entry = FinderMenuItem(path: path + [title], chord: shortcut?.chord, isGlobe: shortcut?.isGlobe ?? false)
            // 同一路径出现两次（按住 ⌥ 才显示的备选项），保留第一个
            if !items.contains(where: { $0.path == entry.path }) {
                items.append(entry)
            }
        }
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // CFGetTypeID 已确认类型，这里的转换一定成功
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func children(_ parent: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &value)
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ parent: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(parent, attribute as CFString, &value)
        return value as? String ?? ""
    }

    private static func integer(_ parent: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(parent, attribute as CFString, &value)
        return value as? Int
    }
}
