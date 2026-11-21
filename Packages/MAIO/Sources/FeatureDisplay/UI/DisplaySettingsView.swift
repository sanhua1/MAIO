import MAIOKit
import SwiftUI

struct DisplaySettingsView: View {
    let settings: any SettingsService
    let controller: DisplayController?
    @State private var value: DisplaySettings

    init(settings: any SettingsService, controller: DisplayController?) {
        self.settings = settings
        self.controller = controller
        _value = State(initialValue: settings.load(DisplaySettings.self))
    }

    var body: some View {
        Form {
            Section {
                Toggle("用音量键调外接显示器的音量", isOn: $value.controlVolume)
                Text("声音从显示器出来（例如音箱接在显示器的耳机口上）、系统没法调音量时，由 MAIO 调显示器自己的音量。耳机、Mac 扬声器等系统能调的输出不受影响。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("用亮度键调外接显示器的亮度", isOn: $value.controlBrightness)
                Text("鼠标在外接显示器上时按亮度键调它；在内建屏上时照常交给系统。菜单栏菜单里也有亮度滑块。⌥⇧ + 音量 / 亮度键微调，⌥ + 音量 / 亮度键打开对应的系统设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let controller {
                DisplayStatusSection(controller: controller)
            }
        }
        .formStyle(.grouped)
        .onChange(of: value) { _, newValue in settings.save(newValue) }
    }
}

/// 检测到的显示器和当前的声音输出，方便排查"为什么按了没反应"
private struct DisplayStatusSection: View {
    let controller: DisplayController

    var body: some View {
        Section("状态") {
            if controller.displays.isEmpty {
                Text(controller.isScanning ? "正在检测外接显示器…" : "没有找到支持 DDC/CI 的外接显示器")
                    .foregroundStyle(.secondary)
            }
            ForEach(controller.displays) { entry in
                LabeledContent(entry.info.name) {
                    Text(capabilities(entry)).foregroundStyle(.secondary)
                }
            }
            LabeledContent("当前声音输出") {
                Text(outputDescription).foregroundStyle(.secondary)
            }
            Button("重新检测") { controller.scheduleScan(after: .zero) }
                .disabled(controller.isScanning)
        }
    }

    private func capabilities(_ entry: DisplayController.Entry) -> String {
        var parts: [String] = []
        if let brightness = entry.brightness {
            parts.append("亮度 \(percent(brightness))")
        }
        if let volume = entry.volume {
            parts.append(volume.isMuted ? "已静音" : "音量 \(percent(volume.value))")
        }
        return parts.isEmpty ? "不支持" : parts.joined(separator: "，")
    }

    private func percent(_ value: VCPValue) -> String {
        "\(Int((Double(value.current) / Double(value.maximum) * 100).rounded()))%"
    }

    private var outputDescription: String {
        guard let output = controller.output else { return "无" }
        if output.canSetVolume {
            return "\(output.name)（系统调节）"
        }
        let handled = VolumeTargeting.display(for: output, among: controller.displays.map(\.info)) != nil
        return "\(output.name)（\(handled ? "MAIO 调节" : "无法调节")）"
    }
}
