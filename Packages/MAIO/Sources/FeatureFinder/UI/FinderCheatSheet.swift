import AppKit
import MAIOKit
import MAIOUI
import SwiftUI

/// 速查面板的一组
struct CheatSheetSection: Identifiable {
    let title: String
    let rows: [(title: String, keys: String)]

    var id: String {
        title
    }
}

/// 在 Finder 里只按住 ⌘ 一会儿，显示当前所有快捷键；松开 ⌘ 或按了别的键就消失。
@MainActor
final class FinderCheatSheet {
    var delay = FinderSettings.defaultValue.cheatSheetDelay
    private let menu: FinderMenuStore
    private var panel: FloatingPanel<CheatSheetView>?
    private var pending: Task<Void, Never>?

    init(menu: FinderMenuStore) {
        self.menu = menu
    }

    func modifiersChanged(_ modifiers: KeyModifiers, settings: FinderSettings) {
        guard modifiers.subtracting(.function) == .command else {
            cancel()
            return
        }
        guard pending == nil, panel?.isVisible != true else { return }
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.pending = nil
            self?.show(settings)
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        hide()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func show(_ settings: FinderSettings) {
        let view = CheatSheetView(sections: Self.sections(settings: settings, menu: menu.items))
        let panel = panel ?? FloatingPanel(rootView: view, size: CGSize(width: 900, height: 600))
        panel.hostingView?.rootView = view
        panel.ignoresMouseEvents = true
        if let size = panel.hostingView?.fittingSize {
            panel.setContentSize(size)
        }
        panel.place(relativeX: 0.5, relativeY: 0.5)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    static func sections(settings: FinderSettings, menu: [FinderMenuItem]) -> [CheatSheetSection] {
        let enhanced = FinderActionID.allCases.compactMap { action in
            settings.chord(for: action).map { (action.info.title, $0.displayString) }
        }
        var sections = enhanced.isEmpty ? [] : [CheatSheetSection(title: "MAIO 增强", rows: enhanced)]
        var order: [String] = []
        var grouped: [String: [(String, String)]] = [:]
        for item in menu where item.chord != nil {
            if grouped[item.menu] == nil {
                order.append(item.menu)
            }
            let title = item.path.count > 2 ? item.path.dropFirst().joined(separator: " › ") : item.title
            grouped[item.menu, default: []].append((title, item.displayChord))
        }
        sections += order.map { CheatSheetSection(title: $0, rows: grouped[$0] ?? []) }
        sections.append(CheatSheetSection(title: "其他按键", rows: otherKeys(settings)))
        return sections
    }

    private static func otherKeys(_ settings: FinderSettings) -> [(String, String)] {
        let renameKey = settings.chord(for: .open)?.keyCode == FinderKeymap.Key.returnKey
            ? (settings.chord(for: .rename)?.displayString ?? "—") : "↩"
        return [
            ("重命名", renameKey), ("快速查看", "Space"), ("按名称跳转", "输入字母"),
            ("展开 / 折叠文件夹（列表）", "→ / ←"), ("展开全部子文件夹（列表）", "⌥→"),
            ("拖动时复制", "⌥ 拖动"), ("拖动时移动", "⌘ 拖动"), ("拖动时制作替身", "⌥⌘ 拖动"),
            ("在新标签页打开文件夹", "⌘ 双击"),
        ]
    }
}

struct CheatSheetView: View {
    let sections: [CheatSheetSection]
    static let columnCount = 4

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(column) { section in sectionView(section) }
                }
                .frame(width: 210, alignment: .leading)
            }
        }
        .padding(22)
        // 不用液态玻璃：面板盖在任意窗口上，透明背景下文字看不清
        .background(.ultraThickMaterial, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator))
    }

    private func sectionView(_ section: CheatSheetSection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(section.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    Text(row.title).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    // 不用等宽字体：等宽字体里 ⌫ 和 ⌦ 几乎一样
                    Text(row.keys).foregroundStyle(.secondary)
                }
                .font(.system(size: 11.5))
            }
        }
    }

    /// 按行数把各组分到几列里，尽量等高
    private var columns: [[CheatSheetSection]] {
        var columns = Array(repeating: [CheatSheetSection](), count: Self.columnCount)
        var heights = Array(repeating: 0, count: Self.columnCount)
        for section in sections {
            let index = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[index].append(section)
            heights[index] += section.rows.count + 2
        }
        return columns.filter { !$0.isEmpty }
    }
}
