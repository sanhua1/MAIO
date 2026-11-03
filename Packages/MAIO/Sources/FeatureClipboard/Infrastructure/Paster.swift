import AppKit
import MAIOKit

// 参考：references/Maccy/Maccy/Clipboard.swift（copy / paste）
/// 把条目写回剪贴板，并（可选）切回原来的 App 模拟 ⌘V。
@MainActor
struct Paster {
    let poster: any SyntheticEventPoster

    /// 写入剪贴板。同一个条目的多种类型都写回，目标 App 自己选择格式。
    func write(_ payload: ClipPayload) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let grouped = Dictionary(grouping: payload.representations, by: \.itemIndex).sorted { $0.key < $1.key }
        let items = grouped.map { _, representations in
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
            }
            return item
        }
        // 标记为 MAIO 写入，监听器会跳过（条目已经在历史里了）
        items.first?.setData(Data(), forType: NSPasteboard.PasteboardType(PasteType.maioMarker))
        pasteboard.writeObjects(items)
    }

    /// 切回 target 并发送 ⌘V。等 target 真正到前台再发，否则按键会落到 MAIO 自己身上。
    func paste(into target: NSRunningApplication?) async {
        if let target, !target.isTerminated, !target.isActive {
            target.activate()
            let deadline = ContinuousClock.now + .milliseconds(600)
            while !target.isActive, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            // 刚激活时窗口的焦点控件可能还没就绪
            try? await Task.sleep(for: .milliseconds(40))
        }
        poster.post(.keyStroke(KeyChord(keyCode: KeyCodes.code(named: "v") ?? 9, modifiers: .command)))
    }
}
