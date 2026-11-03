import AppKit
import MAIOKit
import MAIOUI
import SwiftUI

struct ScrollSettingsView: View {
    let settings: any SettingsService
    @State private var value: ScrollSettings

    init(settings: any SettingsService) {
        self.settings = settings
        _value = State(initialValue: settings.load(ScrollSettings.self))
    }

    var body: some View {
        Group {
            Text("只作用于鼠标滚轮；触控板和妙控鼠标保持系统设置。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle(isOn: $value.reverseVertical) {
                LabelWithInfo("反转纵向滚动", info: ScrollHelp.reverse)
            }
            Toggle("反转横向滚动", isOn: $value.reverseHorizontal)
            Toggle(isOn: $value.smoothEnabled) {
                LabelWithInfo("平滑滚动", info: ScrollHelp.smooth)
            }
            if value.smoothEnabled {
                Toggle("纵向平滑", isOn: $value.smoothVertical)
                Toggle("横向平滑", isOn: $value.smoothHorizontal)
                slider("滚动跨度", info: ScrollHelp.step, value: $value.step, range: ScrollSettings.stepRange, format: "%.0f")
                slider("速度倍率", info: ScrollHelp.speed, value: $value.speed, range: ScrollSettings.speedRange, format: "%.1f×")
                slider(
                    "平滑时长",
                    info: ScrollHelp.duration,
                    value: $value.duration,
                    range: ScrollSettings.durationRange,
                    format: "%.2f",
                )
                LabeledContent {
                    Text("距离 = max(原始距离, 跨度) × 倍率")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } label: {
                    LabelWithInfo("怎么调", info: ScrollHelp.tuning)
                }
            }
            Toggle(isOn: $value.shiftToHorizontal) {
                LabelWithInfo("按住 ⇧ 时横向滚动", info: ScrollHelp.shift)
            }
            zoomRows
            AppExceptionsEditor(exceptions: $value.exceptions)
            HStack {
                Spacer()
                Button("恢复默认设置") { value = .defaultValue }
            }
        }
        .onChange(of: value) { _, newValue in settings.save(newValue) }
    }

    @ViewBuilder private var zoomRows: some View {
        Toggle(isOn: $value.zoomEnabled) {
            LabelWithInfo("按住修饰键 + 滚轮缩放", info: ScrollHelp.zoom)
        }
        if value.zoomEnabled {
            Picker("修饰键", selection: $value.zoomModifier) {
                ForEach(ZoomModifier.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            slider(
                "缩放速度",
                info: ScrollHelp.zoomSpeed,
                value: $value.zoomSpeed,
                range: ScrollSettings.zoomSpeedRange,
                format: "%.1f×",
            )
            Toggle("反转缩放方向", isOn: $value.zoomReversed)
        }
    }

    private func slider(
        _ title: String,
        info: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
    ) -> some View {
        LabeledContent {
            HStack {
                Slider(value: value, in: range).frame(width: 200)
                Text(String(format: format, value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
        } label: {
            LabelWithInfo(title, info: info)
        }
    }
}

/// App 例外列表：在这些 App 里关闭平滑和 / 或反转（例如游戏、远程桌面、绘图软件）。
private struct AppExceptionsEditor: View {
    @Binding var exceptions: [AppException]

    var body: some View {
        LabeledContent {
            Button("添加 App…", action: addApp)
        } label: {
            LabelWithInfo("App 例外", info: ScrollHelp.exceptions)
        }
        ForEach($exceptions) { $exception in
            HStack {
                Text(exception.name)
                Text(exception.bundleID).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("关闭平滑", isOn: $exception.disableSmooth).toggleStyle(.checkbox)
                Toggle("关闭反转", isOn: $exception.disableReverse).toggleStyle(.checkbox)
                Button("移除", systemImage: "minus.circle") {
                    exceptions.removeAll { $0.id == exception.id }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier,
                  !exceptions.contains(where: { $0.bundleID == bundleID }) else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            exceptions.append(AppException(bundleID: bundleID, name: name))
        }
    }
}
