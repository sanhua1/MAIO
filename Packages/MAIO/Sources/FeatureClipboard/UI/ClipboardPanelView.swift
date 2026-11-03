import AppKit
import SwiftUI

/// 剪贴板弹出面板：搜索框 + 历史列表 + 底部按键提示；按空格预览。
struct ClipboardPanelView: View {
    static let size = CGSize(width: 440, height: 460)

    @Bindable var model: ClipboardViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            ZStack {
                ClipListView(model: model)
                if let preview = model.preview {
                    ClipPreviewView(item: preview.item, payload: preview.payload)
                }
            }
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .onAppear { searchFocused = model.isSearching }
        .onChange(of: model.openToken) { _, _ in searchFocused = model.isSearching }
        // 等搜索框解除禁用后（下一轮刷新）再给焦点
        .onChange(of: model.isSearching) { _, searching in
            Task { @MainActor in searchFocused = searching }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(model.isSearching ? "搜索剪贴板历史" : "按 ⌘F 搜索", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onKeyPress(phases: .down, action: handleKey)
                // 不在搜索时禁用，免得窗口一打开就自动把焦点给它；点一下开始搜索
                .disabled(!model.isSearching)
                .overlay {
                    if !model.isSearching {
                        Color.clear.contentShape(.rect).onTapGesture { model.startSearch() }
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        Text(footerText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.vertical, 6)
    }

    private var footerText: String {
        if model.searchMode == .explicit {
            return model.isSearching
                ? "⏎ 完成搜索   Esc 取消搜索   ↑↓ 选择"
                : "⏎ 粘贴   ⌘F 搜索   ⇧⏎ 纯文本   ⌘1–9 快速粘贴   ␣ 预览   ⌘P 固定   ⌫ 删除"
        }
        return "⏎ 粘贴   ⇧⏎ 纯文本   ⌘1–9 快速粘贴   ␣ 预览   ⌘P 固定   ⌘⌫ 删除"
    }

    /// 搜索时搜索框拿着焦点，按键都先经过这里（不在搜索时由面板控制器处理）
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // 输入法正在组字：空格选字、⏎ 上屏、⌫ 删拼音……全部交给输入法
        if model.keyIsComposing {
            return .ignored
        }
        let command = press.modifiers.contains(.command)
        switch press.key {
        case .upArrow: model.move(by: -1)
        case .downArrow: model.move(by: 1)
        case .return:
            if model.searchMode == .explicit {
                model.endSearch(clear: false)
            } else {
                model.pasteSelected(plainText: press.modifiers.contains(.shift))
            }
        case .escape:
            if model.preview != nil {
                model.togglePreview()
            } else if model.searchMode == .explicit {
                model.endSearch(clear: true)
            } else {
                model.onClose?()
            }
        // 搜索框里的空格就是空格；只有"直接打字搜索"模式、还没输入时，空格才是预览
        case .space where model.query.isEmpty && model.searchMode == .typeToSearch: model.togglePreview()
        case .delete where command || (model.query.isEmpty && model.searchMode == .typeToSearch): model.deleteSelected()
        default:
            return handleCommandShortcut(press, command: command)
        }
        return .handled
    }

    private func handleCommandShortcut(_ press: KeyPress, command: Bool) -> KeyPress.Result {
        guard command, let character = press.characters.first else { return .ignored }
        if let digit = character.wholeNumberValue {
            model.pasteQuick(slot: digit)
            return .handled
        }
        if character == "p" {
            model.togglePinSelected()
            return .handled
        }
        return .ignored
    }
}

/// 历史列表。选中项变化时自动滚动到可见位置。
private struct ClipListView: View {
    let model: ClipboardViewModel

    var body: some View {
        if model.picker.items.isEmpty {
            ContentUnavailableView(
                model.query.isEmpty ? "还没有剪贴板历史" : "没有找到",
                systemImage: "list.clipboard",
                description: Text(model.query.isEmpty ? "复制一些内容后再来看看" : "换个关键词试试"),
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.picker.items.enumerated()), id: \.element.id) { index, item in
                            ClipRowView(
                                item: item, model: model,
                                isSelected: index == model.picker.selectedIndex,
                                quickSlot: model.picker.quickSlot(of: item),
                            )
                            .id(item.id)
                            .onTapGesture {
                                model.select(index)
                                model.pasteSelected(plainText: false)
                            }
                            .onHover { inside in
                                if inside {
                                    model.select(index)
                                }
                            }
                            .contextMenu { ClipContextMenu(item: item, model: model) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.picker.selected?.id) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
                .onChange(of: model.openToken) { _, _ in
                    if let first = model.picker.items.first?.id {
                        proxy.scrollTo(first, anchor: .top)
                    }
                }
            }
        }
    }
}
