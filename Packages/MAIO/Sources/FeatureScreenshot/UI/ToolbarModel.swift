import AppKit
import SwiftUI

/// 工具栏发出的操作
enum ToolbarCommand {
    case tool(AnnotationTool)
    case color(AnnotationColor)
    /// 打开系统颜色面板
    case customColor
    /// 文字工具：色板改文字颜色还是背景色
    case textColorTarget(TextColorTarget)
    case textBold
    case textDecoration(TextDecoration)
    /// 大小（pt，连续可调）
    case size(Double)
    case options((inout ToolStyle) -> Void)
    case undo
    case redo
    case cancel
    case save
    case pin
    case ocr
    case translate
    case scrolling
    case record
    case copy
}

/// 鼠标停在工具栏某一块上时用的指针形状
enum ToolbarCursor {
    case arrow
    case iBeam

    var nsCursor: NSCursor {
        switch self {
        case .arrow: .arrow
        case .iBeam: .iBeam
        }
    }
}

/// 鼠标停在哪一块上：显示什么提示、用哪种指针
struct ToolbarHint: Equatable {
    var help: String
    var cursor: ToolbarCursor = .arrow
}

/// 工具栏的状态，由截图流程同步。
@MainActor @Observable
final class ToolbarModel {
    var tool: AnnotationTool?
    /// 选项行对应的工具（选中的对象优先）
    var activeTool: AnnotationTool?
    var style = ToolStyle()
    var canUndo = false
    var canRedo = false
    var nextCounter = 1
    /// 色板上高亮的颜色（文字工具时是文字颜色或背景色）
    var paletteColor = AnnotationColor.red
    /// 当前大小（线宽、字号……）和范围
    var sizeValue = 4.0
    var sizeRange: ClosedRange<Double> = 1 ... 40
    /// 当前这段文字的样式（正在输入 > 选中 > 默认）
    var text = TextAppearance(foreground: .red, background: .white, decoration: .plain, bold: false, fontSize: 18)
    var textColorTarget = TextColorTarget.foreground
    /// 选区是屏幕（不是重新编辑已有截图）：只有这时能长截图、录屏
    var capturesScreen = true
    @ObservationIgnored var perform: (ToolbarCommand) -> Void = { _ in }
    /// 提示变化（nil = 鼠标离开了所有控件或离开工具栏）
    @ObservationIgnored var hintChanged: (ToolbarHint?) -> Void = { _ in }
    /// 当前指针下的提示；同时有多个时取最后进入的那个
    private(set) var hint: ToolbarHint?
    private var active: [ToolbarHint] = []
    /// 指针是否在工具栏范围里（包括按钮之间的空隙）
    private(set) var overToolbar = false

    /// 整块工具栏的 onHover：鼠标在空隙里时也要算"在工具栏上"
    func setOverToolbar(_ inside: Bool) {
        guard inside != overToolbar else { return }
        overToolbar = inside
        if !inside {
            active.removeAll()
        }
        publish()
    }

    /// 子视图的 onHover 回调。相邻控件之间可能先进入后退出，用"集合 + 最后进入"避免闪一下
    func setHover(_ hint: ToolbarHint, inside: Bool) {
        if inside {
            if !active.contains(hint) {
                active.append(hint)
            }
        } else {
            active.removeAll { $0 == hint }
        }
        publish()
    }

    /// 鼠标离开工具栏（或截图结束）时清空，防止提示残留
    func clearHover() {
        active.removeAll()
        overToolbar = false
        publish()
    }

    private func publish() {
        let new = overToolbar ? active.last : nil
        guard new != hint else { return }
        hint = new
        hintChanged(new)
    }
}
