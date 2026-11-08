import AppKit
import MAIOUI
import SwiftUI

/// 选区确定后出现的工具栏（spec 4.1）：
/// 第一行是工具和操作；第二行是颜色和大小；当前工具有专属选项时才出现第三行。
/// 第三行出现、消失时前两行位置不变（工具栏按"三行"的高度定位，见 placeToolbar）。
struct CaptureToolbar: View {
    /// 第三行（含行间距）的高度
    static let optionsRowHeight: CGFloat = 26

    let model: ToolbarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 1) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    iconButton(
                        tool.symbol,
                        help: "\(tool.title)（\(String(tool.key).uppercased())）",
                        selected: model.tool == tool,
                    ) { model.perform(.tool(tool)) }
                }
                divider
                iconButton("arrow.uturn.backward", help: "撤销（⌘Z）") { model.perform(.undo) }
                    .disabled(!model.canUndo)
                iconButton("arrow.uturn.forward", help: "重做（⌘⇧Z）") { model.perform(.redo) }
                    .disabled(!model.canRedo)
                divider
                iconButton("arrow.down.to.line.compact", help: "长截图（⌘L）：自己用滚轮往下滚，自动拼接") { model.perform(.scrolling) }
                    .disabled(!model.capturesScreen)
                iconButton("record.circle", help: "录屏（⌘R）：录 MP4 或 GIF，MP4 可以录系统声音和麦克风") { model.perform(.record) }
                    .disabled(!model.capturesScreen)
                iconButton("text.viewfinder", help: "识别文字（⌘O）") { model.perform(.ocr) }
                iconButton("translate", help: "截图翻译（⌘T）") { model.perform(.translate) }
                divider
                iconButton("square.and.arrow.down", help: "保存（⌘S）") { model.perform(.save) }
                iconButton("pin", help: "贴图（⌘P），同时复制") { model.perform(.pin) }
                iconButton("xmark", help: "取消（Esc）") { model.perform(.cancel) }
                iconButton("checkmark", help: model.confirmHelp) { model.perform(.copy) }
            }
            ToolOptionsRow(model: model)
                .opacity(model.activeTool == nil ? 0.35 : 1)
                .disabled(model.activeTool == nil)
            if model.activeTool?.hasOptions == true {
                ToolSpecificOptions(model: model)
                    .frame(height: Self.optionsRowHeight - 4, alignment: .leading)
                    .font(.callout)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .fixedSize()
        // 宿主视图的高度和内容不一致的那一瞬间，内容贴着顶部，不居中跳动
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 整块工具栏（包括按钮之间的空隙）
        .onHover { model.setOverToolbar($0) }
    }

    private var divider: some View {
        Divider().frame(height: 18).padding(.horizontal, 3)
    }

    private func iconButton(
        _ symbol: String, help: String, selected: Bool = false, action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 26)
                .background(selected ? Color.accentColor.opacity(0.35) : .clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .toolbarHint(help, model: model)
    }
}

/// 工具栏控件的悬停提示。截图的遮罩是自绘窗口，系统自带的 `.help` 提示不会出现，
/// 这里由 `ToolbarModel` 统一记录，截图流程按它设置指针形状并显示提示条。
extension View {
    func toolbarHint(_ help: String, cursor: ToolbarCursor = .arrow, model: ToolbarModel) -> some View {
        onHover { inside in
            model.setHover(ToolbarHint(help: help, cursor: cursor), inside: inside)
        }
        .accessibilityLabel(help)
    }
}

/// 第二行：8 个预设色 + 自定义色、大小。
/// 每一块都是固定宽度，切换工具时工具栏大小和按钮位置不变。
private struct ToolOptionsRow: View {
    static let cell: CGFloat = 22

    let model: ToolbarModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AnnotationColor.presets, id: \.self) { color in
                swatch(color)
            }
            Button { model.perform(.customColor) } label: {
                Circle()
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                    .frame(width: 16, height: 16)
                    .frame(width: Self.cell, height: Self.cell)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .toolbarHint("自定义颜色", model: model)
            divider
            SizeControl(model: model)
        }
        .font(.callout)
    }

    private var divider: some View {
        Divider().frame(height: 18).padding(.horizontal, 3)
    }

    private func swatch(_ color: AnnotationColor) -> some View {
        Button { model.perform(.color(color)) } label: {
            Circle()
                .fill(Color(nsColor: TextRendering.nsColor(color)))
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                .frame(width: 14, height: 14)
                .frame(width: Self.cell, height: Self.cell)
                .overlay {
                    if model.paletteColor == color {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2).frame(width: 20, height: 20)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .toolbarHint(Self.name(of: color), model: model)
    }

    /// 预设色的名字（提示用）
    static func name(of color: AnnotationColor) -> String {
        switch color {
        case AnnotationColor.red: "红色"
        case AnnotationColor.orange: "橙色"
        case AnnotationColor.yellow: "黄色"
        case AnnotationColor.green: "绿色"
        case AnnotationColor.blue: "蓝色"
        case AnnotationColor.purple: "紫色"
        case AnnotationColor.black: "黑色"
        case AnnotationColor.white: "白色"
        default: "颜色"
        }
    }
}

/// 大小：滑块（连续调整）+ 数字输入框（直接输入）。滚轮也可以调整
private struct SizeControl: View {
    let model: ToolbarModel
    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lineweight").foregroundStyle(.secondary)
            Slider(value: value, in: model.sizeRange, step: 1)
                .controlSize(.mini)
                .frame(width: 74)
                .toolbarHint(Self.help, model: model)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 38)
                .focused($editing)
                .onSubmit(commit)
                .onChange(of: editing) { _, isEditing in
                    if !isEditing {
                        commit()
                    }
                }
                .toolbarHint(Self.help, cursor: .iBeam, model: model)
        }
        .onAppear { text = Self.format(model.sizeValue) }
        .onChange(of: model.sizeValue) { _, newValue in
            if !editing {
                text = Self.format(newValue)
            }
        }
    }

    static let help = "大小（线宽、字号等），可以拖动、输入数字或用滚轮调整"

    private var value: SwiftUI.Binding<Double> {
        SwiftUI.Binding(get: { model.sizeValue }, set: { model.perform(.size($0)) })
    }

    private func commit() {
        if let number = Double(text.trimmingCharacters(in: .whitespaces)) {
            model.perform(.size(number))
        }
        text = Self.format(model.sizeValue)
    }

    static func format(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}

/// 文字选项：粗体、外观（分段，三选一）、色板改文字颜色还是背景色
private struct TextOptions: View {
    let model: ToolbarModel

    var body: some View {
        HStack(spacing: 6) {
            Button { model.perform(.textBold) } label: {
                Image(systemName: "bold")
                    .frame(width: 22, height: 20)
                    .background(
                        model.text.bold ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12),
                        in: .rect(cornerRadius: 5),
                    )
            }
            .buttonStyle(.plain)
            .toolbarHint("粗体", model: model)
            segmented
            if model.text.decoration != .plain {
                // 色板改哪种颜色：点哪个，哪个高亮
                HStack(spacing: 2) {
                    colorTarget(.foreground, title: "文字", color: model.text.foreground)
                    colorTarget(.background, title: model.text.decoration.title, color: model.text.background)
                }
            }
        }
    }

    /// 无 / 描边 / 底色：一个分段控件，表示三者只能选一个
    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(TextDecoration.allCases, id: \.self) { decoration in
                Button { model.perform(.textDecoration(decoration)) } label: {
                    Text(decoration.title)
                        .fixedSize()
                        .frame(width: 34, height: 20)
                        .background(model.text.decoration == decoration ? Color.accentColor.opacity(0.45) : .clear)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .toolbarHint("文字外观：\(decoration.title)", model: model)
            }
        }
        .background(Color.secondary.opacity(0.12))
        .clipShape(.rect(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
    }

    private func colorTarget(_ target: TextColorTarget, title: String, color: AnnotationColor) -> some View {
        Button { model.perform(.textColorTarget(target)) } label: {
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: TextRendering.nsColor(color)))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.secondary, lineWidth: 0.5))
                    .frame(width: 11, height: 11)
                Text(title).fixedSize()
            }
            .padding(.horizontal, 5)
            .frame(height: 20)
            .background(
                model.textColorTarget == target ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12),
                in: .rect(cornerRadius: 5),
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .toolbarHint("色板修改\(title)颜色", model: model)
    }
}

/// 各工具特有的选项（放在固定宽度的区域里）
private struct ToolSpecificOptions: View {
    let model: ToolbarModel

    var body: some View {
        HStack(spacing: 4) {
            switch model.activeTool {
            case .rectangle:
                chip("实心", help: "实心填充", model.style.filled) { $0.filled.toggle() }
                chip("圆角", help: "圆角矩形", model.style.rounded) { $0.rounded.toggle() }
            case .ellipse:
                chip("实心", help: "实心填充", model.style.filled) { $0.filled.toggle() }
            case .line:
                chip("虚线", help: "画虚线", model.style.dashed) { $0.dashed.toggle() }
            case .text:
                TextOptions(model: model)
            case .counter:
                Text("下一个 \(model.nextCounter)").monospacedDigit()
                Text("滚轮调整").foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
        .lineLimit(1)
    }

    private func chip(
        _ title: String, help: String, _ isOn: Bool, change: @escaping (inout ToolStyle) -> Void,
    ) -> some View {
        Button { model.perform(.options(change)) } label: {
            Text(title)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isOn ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .toolbarHint(help, model: model)
    }
}

extension TextDecoration {
    var title: String {
        switch self {
        case .plain: "无"
        case .outline: "描边"
        case .background: "底色"
        }
    }
}

extension AnnotationTool {
    /// 有专属选项（工具栏第三行）
    var hasOptions: Bool {
        switch self {
        case .rectangle, .ellipse, .line, .text, .counter: true
        default: false
        }
    }
}
