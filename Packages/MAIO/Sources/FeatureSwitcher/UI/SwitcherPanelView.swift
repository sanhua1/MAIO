import AppKit
import MAIOUI
import SwiftUI

/// 切换面板：自动换行的网格，选中项高亮。
struct SwitcherPanelView: View {
    let model: SwitcherViewModel

    static func cellWidth(thumbnails: Bool) -> CGFloat {
        thumbnails ? 220 : 120
    }

    static let spacing: CGFloat = 12
    static let padding: CGFloat = 16

    /// 屏幕宽度最多能放几列
    static func maxColumns(screenWidth: CGFloat, thumbnails: Bool) -> Int {
        let usable = screenWidth * 0.9 - padding * 2 + spacing
        return max(1, Int(usable / (cellWidth(thumbnails: thumbnails) + spacing)))
    }

    var body: some View {
        Grid(alignment: .top, horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
            // 只用 rows 里的值，不要用序号去 model.items 取值（见 SwitcherCellSlot 的说明）
            ForEach(SwitcherLayout.rows(items: model.items, columns: model.columns)) { row in
                GridRow {
                    ForEach(row.slots) { slot in
                        SwitcherCell(
                            model: model,
                            item: slot.item,
                            isSelected: slot.index == model.selectedIndex,
                            isHovered: model.hoveredID == slot.item.id,
                            width: Self.cellWidth(thumbnails: model.showThumbnails),
                        )
                        // 悬停只高亮，不选中：面板弹出时鼠标恰好停在某一项上，也不会改变要切换的窗口
                        .onHover { inside in
                            if inside {
                                model.hoveredID = slot.item.id
                            } else if model.hoveredID == slot.item.id {
                                model.hoveredID = nil
                            }
                        }
                        .onTapGesture { model.onClick?(slot.index) }
                    }
                }
            }
        }
        .padding(Self.padding)
        .panelGlass(cornerRadius: 22)
        .fixedSize()
    }
}

private struct SwitcherCell: View {
    let model: SwitcherViewModel
    let item: SwitcherItem
    let isSelected: Bool
    let isHovered: Bool
    let width: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            preview
                .frame(width: width - 16, height: model.showThumbnails ? (width - 16) * 0.62 : 72)
            HStack(spacing: 6) {
                if model.showThumbnails, let icon = model.icons[item.pid] {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                Text(item.displayTitle)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: width - 16)
            .opacity(item.isMinimized || item.isHidden ? 0.6 : 1)
        }
        .padding(8)
        .background(background, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .contentShape(.rect)
    }

    private var background: Color {
        if isSelected {
            return Color.accentColor.opacity(0.35)
        }
        return isHovered ? Color.primary.opacity(0.12) : .clear
    }

    @ViewBuilder private var preview: some View {
        if model.showThumbnails, let thumbnail = model.thumbnails[item.id] {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 6))
                .shadow(radius: 2)
        } else if let icon = model.icons[item.pid] {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 72, maxHeight: 72)
        } else {
            Image(systemName: "macwindow").font(.largeTitle).foregroundStyle(.secondary)
        }
    }
}
