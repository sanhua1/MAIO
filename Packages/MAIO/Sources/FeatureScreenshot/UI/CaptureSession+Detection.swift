import AppKit

/// 截图时识别鼠标下的窗口和控件、取色、鼠标指针形状。
extension CaptureSession {

    // MARK: 识别窗口和控件

    var detectsControls: Bool {
        options.alwaysDetectControls || commandHeld
    }

    func updateHover() {
        guard interaction.selection == nil, !interaction.isDragging, let display = display(at: cursor) else {
            highlight = nil
            return
        }
        let bounds = display.display.bounds
        let window = WindowPicker.window(at: cursor, in: windows)
        // 鼠标下没有窗口（桌面）时高亮整个屏幕
        let windowRect = window.map { $0.frame.intersection(bounds) } ?? bounds
        highlight = windowRect
        if let window, detectsControls {
            requestElement(ElementRequest(point: cursor, pid: window.pid, windowID: window.id, clip: windowRect))
        }
    }

    /// 只保留最新一次查询：查询进行中又移动了鼠标，就等这次结束后查最新的位置
    func requestElement(_ request: ElementRequest) {
        pendingElement = request
        guard elementTask == nil else { return }
        elementTask = Task { [weak self] in
            while let request = self?.pendingElement {
                self?.pendingElement = nil
                // MAIO 自己的窗口：遮罩在最上层，跨进程的辅助功能查询会命中遮罩，改为在本进程里直接问那个窗口
                let frame = request.pid == getpid()
                    ? ElementLocator.ownFrame(at: request.point, windowID: request.windowID)
                    : await self?.locator.frame(at: request.point, pid: request.pid)
                guard let self, !Task.isCancelled else { return }
                if self.pendingElement == nil, self.cursor == request.point, self.detectsControls,
                   self.interaction.selection == nil, !self.interaction.isDragging, let frame {
                    let clipped = frame.intersection(request.clip)
                    if !clipped.isNull, clipped.width >= 1, clipped.height >= 1 {
                        self.highlight = clipped
                        self.render()
                    }
                }
            }
            self?.elementTask = nil
        }
    }

    // MARK: 辅助

    func display(at point: CGPoint) -> FrozenDisplay? {
        frozen.first { $0.display.bounds.contains(point) }
            ?? frozen.min { distance($0.display.bounds, point) < distance($1.display.bounds, point) }
    }

    func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let clamped = SelectionGeometry.clamp(point, to: rect)
        return hypot(clamped.x - point.x, clamped.y - point.y)
    }

    func updateColor() {
        guard let display = display(at: cursor) else { return }
        let bounds = display.display.bounds
        let x = Int(((cursor.x - bounds.minX) * display.scale).rounded(.down))
        let y = Int(((cursor.y - bounds.minY) * display.scale).rounded(.down))
        color = PixelSampler.color(in: display.image, x: x, y: y)
    }

    func updateCursorShape() {
        // 工具栏上还原成普通指针（文字框里是 I 形），不再显示十字
        if isOverToolbar(cursor) {
            (toolbarHint?.cursor ?? .arrow).nsCursor.set()
            return
        }
        guard let selection = interaction.selection else {
            NSCursor.crosshair.set()
            return
        }
        if let selected = editor.document.selected, let handle = selected.handle(at: cursor) {
            switch handle {
            case let .frame(side): NSCursor.frameResize(position: side.cursorPosition, directions: .all).set()
            case .start, .end: NSCursor.crosshair.set()
            }
        } else if let handle = SelectionGeometry.handle(at: cursor, in: selection) {
            NSCursor.frameResize(position: handle.cursorPosition, directions: .all).set()
        } else if editor.document.selected?.contains(cursor) == true
            || (editor.tool == nil && editor.document.hit(at: cursor) != nil) {
            NSCursor.pointingHand.set()
        } else if let tool = editor.tool, selection.contains(cursor) {
            (tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
        } else if selection.contains(cursor), editor.tool == nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }
}

extension SelectionHandle {
    var cursorPosition: NSCursor.FrameResizePosition {
        switch self {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .right: .right
        case .bottomRight: .bottomRight
        case .bottom: .bottom
        case .bottomLeft: .bottomLeft
        case .left: .left
        }
    }
}
