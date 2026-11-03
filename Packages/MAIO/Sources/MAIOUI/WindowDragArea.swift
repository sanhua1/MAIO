import AppKit
import SwiftUI

/// 拖动这块区域移动窗口（放在标题栏背景上）。
/// 用它代替 `isMovableByWindowBackground`：后者让窗口任何地方都能拖动，会抢走文字选择。
public struct WindowDragArea: NSViewRepresentable {
    public init() {}

    public func makeNSView(context _: Context) -> NSView {
        DragView()
    }

    public func updateNSView(_: NSView, context _: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
            true
        }
    }
}
