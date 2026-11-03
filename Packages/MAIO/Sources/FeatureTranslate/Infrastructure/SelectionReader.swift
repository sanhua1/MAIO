import AppKit
import ApplicationServices
import MAIOKit

// 参考：references/pot-desktop/src-tauri/src/window.rs（selection_translate 先取选中文字的流程）
/// 读取当前 App 里选中的文字。
/// 1. 先通过辅助功能读取（不影响剪贴板）；
/// 2. 读不到时（Chrome、Electron 等常见）模拟 ⌘C，读出后把剪贴板恢复原样。
@MainActor
struct SelectionReader {
    let poster: any SyntheticEventPoster

    /// 等待目标 App 响应 ⌘C 的最长时间
    static let copyTimeout: Duration = .milliseconds(350)

    func read() async -> String? {
        if let text = Self.accessibilitySelection(), !text.isBlank {
            return text
        }
        return await copySelection()
    }

    static func accessibilitySelection() -> String? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        // CFGetTypeID 已确认类型，这里的转换一定成功
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success
        else { return nil }
        return selected as? String
    }

    private func copySelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        poster.post(.keyStroke(KeyChord(keyCode: KeyCodes.code(named: "c") ?? 8, modifiers: .command)))
        let deadline = ContinuousClock.now + Self.copyTimeout
        while pasteboard.changeCount == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(15))
        }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        saved.restore(to: pasteboard)
        return text.flatMap { $0.isBlank ? nil : $0 }
    }
}

/// 剪贴板内容的完整副本（所有条目、所有类型），用于模拟 ⌘C 后恢复。
@MainActor
private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(
                item.types.compactMap { type in item.data(forType: type).map { (type, $0) } },
                uniquingKeysWith: { first, _ in first },
            )
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { values in
            let item = NSPasteboardItem()
            values.forEach { item.setData($1, forType: $0) }
            return item
        }
        // nspasteboard.org 约定的"恢复"标记：剪贴板历史（MAIO 自己的、或 Maccy 等）会跳过这次写入
        restored.first?.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.RestoredType"))
        pasteboard.writeObjects(restored)
    }
}

extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
