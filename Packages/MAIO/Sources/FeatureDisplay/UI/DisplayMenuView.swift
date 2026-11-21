import AppKit
import SwiftUI

/// 菜单栏菜单最上面的外接显示器控制：每台显示器一组，名字下面是亮度条，
/// 声音正从这台显示器出来（音量键在调它）时再加一条音量条。
struct DisplayMenuView: View {
    let controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(controller.menuDisplays) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.info.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if let brightness = entry.brightness {
                        SliderRow(low: "sun.min.fill", high: "sun.max.fill", value: fraction(brightness)) {
                            controller.setBrightness($0, on: entry.id)
                        }
                    }
                    if controller.hasMenuVolume(entry), let volume = entry.volume {
                        SliderRow(
                            low: volume.isMuted ? "speaker.slash.fill" : "speaker.fill",
                            high: "speaker.wave.3.fill",
                            value: volume.isMuted ? 0 : fraction(volume.value),
                        ) { controller.setVolume($0, on: entry.id) }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .onAppear { controller.refreshMenuLevels() }
    }

    private func fraction(_ value: VCPValue) -> Double {
        Double(value.current) / Double(value.maximum)
    }
}

/// 两头带图标的一条滑块
private struct SliderRow: View {
    let low: String
    let high: String
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: low).foregroundStyle(.secondary).frame(width: 18)
            MenuSlider(value: value, onChange: onChange)
            Image(systemName: high).foregroundStyle(.secondary).frame(width: 22)
        }
    }
}

/// 菜单里用 AppKit 的 NSSlider：菜单跟踪鼠标时它拖动最可靠，拖动过程中连续回调
struct MenuSlider: NSViewRepresentable {
    let value: Double
    let onChange: (Double) -> Void

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value, minValue: 0, maxValue: 1,
            target: context.coordinator, action: #selector(Coordinator.changed(_:)),
        )
        slider.isContinuous = true
        slider.controlSize = .regular
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.onChange = onChange
        // 拖动中不要用读回来的值把滑块拽回去
        if NSEvent.pressedMouseButtons == 0, abs(slider.doubleValue - value) > 0.001 {
            slider.doubleValue = value
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onChange: (Double) -> Void

        init(onChange: @escaping (Double) -> Void) {
            self.onChange = onChange
        }

        @objc func changed(_ sender: NSSlider) {
            onChange(sender.doubleValue)
        }
    }
}
