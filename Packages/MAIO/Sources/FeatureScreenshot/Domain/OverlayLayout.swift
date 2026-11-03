import CoreGraphics

/// 遮罩上各个浮动元素的位置（全局坐标，左上角原点）。
enum OverlayLayout {
    static let gap: CGFloat = 8

    /// 工具栏：优先放在选区下方，放不下依次换到上方、选区内部（Flameshot 的规则）。右边和选区对齐。
    static func toolbarFrame(size: CGSize, selection: CGRect, bounds: CGRect) -> CGRect {
        let x = min(max(selection.maxX - size.width, bounds.minX + gap), bounds.maxX - size.width - gap)
        let below = selection.maxY + gap
        let above = selection.minY - gap - size.height
        let y = if below + size.height <= bounds.maxY - gap {
            below
        } else if above >= bounds.minY + gap {
            above
        } else {
            max(selection.maxY - gap - size.height, bounds.minY + gap)
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// 尺寸标签：放在选区左上角外侧，放不下时放到内侧。
    static func sizeLabelFrame(size: CGSize, selection: CGRect, bounds: CGRect) -> CGRect {
        let outsideY = selection.minY - size.height - 4
        let y = outsideY >= bounds.minY ? outsideY : selection.minY + 4
        let x = min(max(selection.minX, bounds.minX), bounds.maxX - size.width)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// 放大镜：默认在鼠标右下方，靠近屏幕边缘时换到另一侧。
    static func magnifierFrame(size: CGSize, cursor: CGPoint, bounds: CGRect) -> CGRect {
        let offset: CGFloat = 20
        var x = cursor.x + offset
        if x + size.width > bounds.maxX {
            x = cursor.x - offset - size.width
        }
        var y = cursor.y + offset
        if y + size.height > bounds.maxY {
            y = cursor.y - offset - size.height
        }
        return CGRect(origin: CGPoint(x: max(x, bounds.minX), y: max(y, bounds.minY)), size: size)
    }
}
