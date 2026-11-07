import AppKit
import SwiftUI

/// 不抢焦点的浮动面板（HUD、剪贴板面板、切换器、启动器、翻译等共用）。
/// 全部用 `nonactivatingPanel`：成为键盘窗口时不会把 MAIO 激活到前台，顶部菜单栏保持原来的 App
/// （普通窗口一旦激活，macOS 会把菜单栏换成 MAIO 的「MAIO 编辑 窗口」）。需要打字的用 `acceptsKeyboard` 打开 `canBecomeKey`。
@MainActor
public final class FloatingPanel<Content: View>: NSPanel {
    private let acceptsKeyboard: Bool

    public init(rootView: Content, size: CGSize = CGSize(width: 320, height: 80), acceptsKeyboard: Bool = false) {
        self.acceptsKeyboard = acceptsKeyboard
        let style: NSWindow.StyleMask = [.borderless, .fullSizeContentView, .nonactivatingPanel]
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        // 系统的窗口阴影（和别的 App 的浮动窗口一样）。透明窗口的阴影按内容的不透明部分算，圆角面板就是圆角阴影
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = [.intrinsicContentSize]
        contentView = hosting
    }

    /// 按 ⌘W（主菜单「窗口 › 关闭」）时调用，交给控制器走自己的关闭流程（取消请求、把焦点还给原来的 App 等）。
    /// 无边框面板没有关闭按钮，系统默认的 `performClose` 什么也不做；不设置时 ⌘W 对这个面板无效。
    public var onCloseCommand: (() -> Void)?

    /// 无边框窗口默认不能成为 key window（无法输入文字），需要键盘输入的面板要打开。
    override public var canBecomeKey: Bool {
        acceptsKeyboard || super.canBecomeKey
    }

    override public func performClose(_ sender: Any?) {
        guard let onCloseCommand else {
            super.performClose(sender)
            return
        }
        onCloseCommand()
    }

    /// 系统按"有没有关闭按钮"判断「关闭」能不能用，无边框面板总是不能用（⌘W 不会发过来）
    override public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performClose(_:)), onCloseCommand != nil {
            return true
        }
        return super.validateMenuItem(menuItem)
    }

    /// 透明窗口的阴影形状是按当时画出来的内容算好缓存的：显示和改变大小后等内容画完再重算一次，
    /// 否则阴影会是空的或者停在旧的大小
    override public func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        refreshShadow()
    }

    override public func orderFrontRegardless() {
        super.orderFrontRegardless()
        refreshShadow()
    }

    override public func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        refreshShadow()
    }

    private func refreshShadow() {
        DispatchQueue.main.async { [weak self] in
            self?.invalidateShadow()
        }
    }

    public var hostingView: NSHostingView<Content>? {
        contentView as? NSHostingView<Content>
    }

    /// 放在鼠标所在屏幕的指定相对位置（0...1，原点在左下）。
    public func place(relativeX: CGFloat = 0.5, relativeY: CGFloat = 0.5) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = hostingView?.fittingSize ?? self.frame.size
        setContentSize(size)
        setFrameOrigin(CGPoint(
            x: frame.minX + (frame.width - size.width) * relativeX,
            y: frame.minY + (frame.height - size.height) * relativeY,
        ))
    }
}
