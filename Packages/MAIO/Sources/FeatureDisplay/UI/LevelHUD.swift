import AppKit
import MAIOUI
import Observation
import SwiftUI

/// 亮度 / 音量浮窗，仿照系统的样式（图标 + 16 格进度条）：屏幕右上角、菜单栏下面，停手 1.5 秒后淡出。
/// （系统自己的浮窗接口 OSDManager 在 macOS 27 上调用不报错但不显示，所以自己画）
@MainActor
final class LevelHUD {
    enum Kind: Equatable {
        case brightness
        case volume(muted: Bool)
    }

    @MainActor
    @Observable
    final class Model {
        var symbol = "sun.max.fill"
        var title = ""
        var fraction = 0.0
    }

    private let model = Model()
    private var panel: FloatingPanel<LevelHUDView>?
    private var hideTask: Task<Void, Never>?

    func show(_ kind: Kind, fraction: Double, on display: CGDirectDisplayID) {
        // 显示器只收整数：第 7 格是 43.75%，写进去是 44%。对齐到最近的 1/4 格再画，否则会多亮出一小条
        let steps = Double(ChicletBar.count * 4)
        model.fraction = (min(max(fraction, 0), 1) * steps).rounded() / steps
        switch kind {
        case .brightness:
            model.title = "亮度"
            model.symbol = fraction < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case let .volume(muted):
            model.title = muted ? "静音" : "音量"
            model.symbol = Self.volumeSymbol(fraction: fraction, muted: muted)
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        place(panel, on: display)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        scheduleHide()
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel<LevelHUDView> {
        let panel = FloatingPanel(rootView: LevelHUDView(model: model), size: CGSize(width: 300, height: 70))
        panel.ignoresMouseEvents = true
        return panel
    }

    private func place(_ panel: NSPanel, on display: CGDirectDisplayID) {
        let screen = NSScreen.screens.first { $0.displayID == display } ?? NSScreen.main
        guard let screen else { return }
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let visible = screen.visibleFrame
        let origin = CGPoint(x: visible.maxX - size.width - 10, y: visible.maxY - size.height - 6)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let panel = self?.panel else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private static func volumeSymbol(fraction: Double, muted: Bool) -> String {
        if muted || fraction <= 0 {
            return "speaker.slash.fill"
        }
        return switch fraction {
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

struct LevelHUDView: View {
    let model: LevelHUD.Model

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.symbol)
                .font(.system(size: 26, weight: .regular))
                // 各个符号的高度不一样（静音的喇叭、小太阳都更矮/更高），定死高度，否则浮窗会跟着图标变高变矮
                .frame(width: 40, height: 32, alignment: .leading)
                .contentTransition(.symbolEffect(.replace))
            ChicletBar(fraction: model.fraction)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 300)
        .panelGlass(cornerRadius: 16)
        .padding(10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.title)
        .accessibilityValue("\(Int((model.fraction * 100).rounded()))%")
    }
}

/// 系统样式的 16 格进度条：每格单独点亮，微调（1/64）时一格亮四分之一
struct ChicletBar: View {
    let fraction: Double
    static let count = 16

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< Self.count, id: \.self) { index in
                let fill = min(max(fraction * Double(Self.count) - Double(index), 0), 1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.35))
                        Rectangle().fill(.white).frame(width: proxy.size.width * fill)
                    }
                }
            }
        }
        .frame(height: 6)
        .clipShape(.rect(cornerRadius: 1.5))
    }
}
