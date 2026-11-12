import MAIOUI
import SwiftUI

/// 启动器面板：搜索框 → 来源标签 → 结果列表 → 按键提示。尺寸固定（不随结果数变化，顶部位置不会跳）。
struct LauncherPanelView: View {
    static let size = CGSize(width: 720, height: 480)
    static let rowHeight: CGFloat = 44
    /// 搜索框这一行的高度（面板最上面）
    static let searchHeight: CGFloat = 56

    @Bindable var model: LauncherViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            SourceTabs(model: model)
            Divider()
            LauncherResultList(model: model)
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .panelGlass(cornerRadius: 20)
        .onAppear { searchFocused = true }
        .onChange(of: model.openToken) { _, _ in searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索应用、文件、网页…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($searchFocused)
        }
        .padding(.horizontal, 18)
        .frame(height: Self.searchHeight)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("⏎", "打开")
            hint("⌘⏎", "在 Finder 中显示")
            hint("⌘C", "复制路径")
            hint("⌘1–9", "快速打开")
            hint("⇥", "切换来源")
            Spacer()
            hint("Esc", "关闭")
            Button {
                model.onOpenSettings?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .frame(width: 20, height: 20)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("MAIO 设置")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 28)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key).fontWeight(.semibold)
            Text(text)
        }
    }
}

/// 来源标签：全部 · 应用 · …；输入前缀时高亮前缀对应的来源
private struct SourceTabs: View {
    let model: LauncherViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(LauncherSource.available, id: \.self) { source in
                let isOn = source == model.effectiveSource
                Text(source.title)
                    .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(isOn ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear), in: .capsule)
                    .contentShape(.capsule)
                    .onTapGesture { model.selectedSource = source }
            }
            Spacer()
            if let engine = model.parsed.engine {
                Text("网页搜索：\(engine.name)").font(.caption).foregroundStyle(.secondary)
            } else if let status = model.fileStatusText {
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

/// 分组的结果列表。选中项变化时滚动到可见位置。
private struct LauncherResultList: View {
    let model: LauncherViewModel

    var body: some View {
        if model.items.isEmpty {
            emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        ForEach(model.sections) { section in
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                            ForEach(section.items) { item in
                                row(item)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                .onChange(of: model.selected?.id) { _, id in
                    if let id {
                        proxy.scrollTo(id)
                    }
                }
                .onChange(of: model.openToken) { _, _ in
                    if let first = model.items.first?.id {
                        proxy.scrollTo(first, anchor: .top)
                    }
                }
            }
        }
    }

    private func row(_ item: LauncherItem) -> some View {
        let index = model.items.firstIndex { $0.id == item.id } ?? 0
        return LauncherRow(
            item: item, icon: model.icons.icon(for: item),
            isSelected: index == model.selectedIndex, slot: index < 9 ? index + 1 : nil,
        )
        .id(item.id)
        .contentShape(.rect)
        .onTapGesture {
            model.select(index)
            model.openSelected(reveal: false)
        }
        .modifier(FileDrag(item: item, icon: model.icons.icon(for: item)))
    }

    @ViewBuilder private var emptyState: some View {
        if model.parsed.isEmpty {
            Text("输入应用、文件或命令的名称（支持拼音和首字母）；> 开头只搜命令；g / bd + 空格 + 内容进行网页搜索")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(40)
        } else {
            Text("没有找到").font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// 应用、文件可以直接拖出去（拖到程序坞、AppCleaner、访达、别的 App 里），和从访达拖一样是文件 URL
private struct FileDrag: ViewModifier {
    let item: LauncherItem
    let icon: NSImage

    func body(content: Content) -> some View {
        if let path = item.path {
            content.onDrag {
                NSItemProvider(object: URL(filePath: path) as NSURL)
            } preview: {
                Image(nsImage: icon).resizable().frame(width: 48, height: 48)
            }
        } else {
            content
        }
    }
}

private struct LauncherRow: View {
    let item: LauncherItem
    let icon: NSImage
    let isSelected: Bool
    let slot: Int?

    var body: some View {
        HStack(spacing: 10) {
            iconView
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 14)).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            Text(item.kindLabel).font(.caption).foregroundStyle(.secondary)
            if let slot {
                Text("⌘\(slot)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 26)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: LauncherPanelView.rowHeight)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder private var iconView: some View {
        if let symbol = item.symbolName {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(item.kindLabel == "MAIO" ? AnyShapeStyle(.tint) : AnyShapeStyle(.gray), in: .rect(cornerRadius: 6))
                .frame(width: 28, height: 28)
        } else {
            Image(nsImage: icon).resizable().frame(width: 28, height: 28)
        }
    }
}
