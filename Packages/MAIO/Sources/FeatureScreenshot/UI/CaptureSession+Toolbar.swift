import AppKit

/// 工具栏的悬停：指针形状和提示条。
/// 遮罩窗口把鼠标事件交给 `OverlayView`（第一响应者），所以系统按视图自动切换指针的机制不生效，
/// 这里统一按"指针是否在工具栏上、停在哪个控件上"决定。
extension CaptureSession {
    /// 工具栏在全局坐标（左上角原点，pt）里的范围
    var toolbarGlobalFrame: CGRect? {
        guard !toolbar.isHidden, let view = toolbar.superview as? OverlayView else { return nil }
        let frame = toolbar.frame
        return CGRect(
            x: view.display.bounds.minX + frame.minX,
            y: view.display.bounds.minY + view.bounds.height - frame.maxY,
            width: frame.width,
            height: frame.height,
        )
    }

    func isOverToolbar(_ point: CGPoint) -> Bool {
        toolbarGlobalFrame?.contains(point) ?? false
    }

    /// 鼠标离开工具栏或截图结束时，清掉悬停状态和提示
    func clearToolbarHover() {
        guard toolbarHint != nil || toolbarModel.hint != nil else { return }
        toolbarHint = nil
        toolbarTooltip.hide()
        toolbarModel.clearHover()
    }

    /// `ToolbarModel` 报告指针下的控件变了：立刻换提示（没有延迟）
    func toolbarHoverChanged(_ hint: ToolbarHint?) {
        toolbarHint = hint
        // 指针形状跟着悬停的控件走（工具栏上不再显示十字）
        if isOverToolbar(cursor) {
            (hint?.cursor ?? .arrow).nsCursor.set()
        } else {
            updateCursorShape()
        }
        guard let hint, !finished else {
            toolbarTooltip.hide()
            return
        }
        toolbarTooltip.show(hint.help)
    }
}
