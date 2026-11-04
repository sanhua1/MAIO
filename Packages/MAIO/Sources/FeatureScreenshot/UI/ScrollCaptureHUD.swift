import AppKit
import MAIOUI
import SwiftUI

/// 长截图的状态（右侧面板显示）
@MainActor @Observable
final class ScrollCaptureModel {
    /// 已拼好的高度（像素）
    var height = 0
    /// 选区高度（像素）
    var frameHeight = 0
    /// 当前画面顶部在长图中的位置（画布坐标）
    var position = 0
    /// 长条预览（已拼好的整张图缩小）
    var preview: CGImage?
    /// 对不上时的提示
    var warning: String?
    @ObservationIgnored var finish: () -> Void = {}
}

/// 选区右侧的竖条面板：高度、完成按钮、长条预览（绿框 = 当前画面在长图中的位置）
struct ScrollCaptureSidebar: View {
    static let width: CGFloat = 180

    @Bindable var model: ScrollCaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(model.height) px").font(.callout.monospacedDigit())
                Spacer()
                Button("完成") { model.finish() }
            }
            Text(model.warning ?? "用滚轮往下滚动\nEsc 或 ⏎ 完成")
                .font(.caption)
                .foregroundStyle(model.warning == nil ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            if let preview = model.preview {
                previewView(preview)
            }
        }
        .padding(10)
        .frame(width: Self.width)
        .panelGlass(cornerRadius: 12)
        // 面板比内容高：内容贴着顶部，下面透明（点击会穿透）
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func previewView(_ preview: CGImage) -> some View {
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / CGFloat(max(preview.width, 1)),
                proxy.size.height / CGFloat(max(preview.height, 1)),
            )
            let width = CGFloat(preview.width) * scale
            let height = CGFloat(preview.height) * scale
            let total = CGFloat(max(model.height, 1))
            let frameHeight = min(height, CGFloat(model.frameHeight) / total * height)
            let top = min(height - frameHeight, max(0, CGFloat(model.position) / total * height))
            Image(decorative: preview, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: height)
                .overlay(alignment: .topLeading) {
                    Rectangle()
                        .stroke(Color.green, lineWidth: 1)
                        .frame(width: width, height: max(2, frameHeight))
                        .offset(y: top)
                }
                .overlay(Rectangle().stroke(.separator))
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(minHeight: 120)
    }
}

/// 选区外 1 px 的虚线边框（不挡鼠标）和右侧面板。两者都是 MAIO 的窗口，截图时会被排除
@MainActor
final class ScrollCaptureFrame {
    private let border: NSPanel
    private let sidebar: NSPanel

    /// rect：全局坐标（左上角原点，pt）
    init(rect: CGRect, model: ScrollCaptureModel) {
        let frame = Self.appKitRect(rect)
        border = Self.panel(frame: frame.insetBy(dx: -2, dy: -2))
        border.ignoresMouseEvents = true
        border.contentView = BorderView(frame: CGRect(origin: .zero, size: border.frame.size))
        sidebar = Self.panel(frame: Self.sidebarFrame(beside: frame))
        sidebar.contentView = NSHostingView(rootView: ScrollCaptureSidebar(model: model))
    }

    func show() {
        border.orderFrontRegardless()
        sidebar.orderFrontRegardless()
    }

    func close() {
        border.close()
        sidebar.close()
    }

    private static func panel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    /// 选区右边，顶部对齐，一直延伸到屏幕底部；右边放不下放左边，都放不下就放在选区里靠右
    private static func sidebarFrame(beside frame: CGRect) -> CGRect {
        let visible = (NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main)?.visibleFrame ?? frame
        let width = ScrollCaptureSidebar.width
        let gap: CGFloat = 10
        let x: CGFloat = if frame.maxX + gap + width <= visible.maxX {
            frame.maxX + gap
        } else if frame.minX - gap - width >= visible.minX {
            frame.minX - gap - width
        } else {
            min(frame.maxX, visible.maxX) - width - gap
        }
        let top = min(frame.maxY, visible.maxY)
        let bottom = visible.minY + gap
        return CGRect(x: x, y: bottom, width: width, height: max(160, top - bottom))
    }

    private static func appKitRect(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private final class BorderView: NSView {
        override func draw(_: NSRect) {
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.stroke()
        }
    }
}
