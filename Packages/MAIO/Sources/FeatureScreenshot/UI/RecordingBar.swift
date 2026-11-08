import AppKit
import MAIOUI
import SwiftUI

/// 录屏控制条的状态
@MainActor @Observable
final class RecordingModel {
    enum Phase {
        /// 选格式、声音，等用户按开始
        case setup
        case recording
        /// 停止后写文件
        case saving
    }

    var phase = Phase.setup
    var options: RecordingOptions
    var elapsed: Duration = .zero
    /// 提示（例如麦克风没有授权）
    var message: String?

    @ObservationIgnored var start: () -> Void = {}
    @ObservationIgnored var stop: () -> Void = {}
    @ObservationIgnored var cancel: () -> Void = {}

    /// 选区大小（pt）和每 pt 的像素数，用来显示输出尺寸
    private let points: CGSize
    private let scale: CGFloat

    init(options: RecordingOptions, points: CGSize, scale: CGFloat) {
        self.options = options
        self.points = points
        self.scale = scale
    }

    /// 输出尺寸，如 "1280 × 720"（GIF 默认按 pt 录，切换格式时跟着变）
    var sizeText: String {
        let size = RecordingGeometry.outputSize(points: points, scale: scale, options: options)
        return "\(size.width) × \(size.height)"
    }

    var elapsedText: String {
        let seconds = Int(elapsed.components.seconds)
        let minutes = seconds / 60
        return String(format: "%02d:%02d", minutes, seconds % 60)
    }
}

/// 选区下方的控制条：开始前选 MP4 / GIF、系统声音、麦克风；录制中显示时间、完成、放弃。
/// 每一块都是固定宽度，切换格式、开关声音、开始录制时控制条的大小和各按钮的位置都不变。
struct RecordingBar: View {
    static let size = CGSize(width: 440, height: 44)
    private static let buttonWidth: CGFloat = 76

    @Bindable var model: RecordingModel

    var body: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .setup: setup
            case .recording: recording
            case .saving:
                Spacer()
                ProgressView().controlSize(.small)
                Text("正在保存…").font(.callout)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(width: Self.size.width, height: Self.size.height)
        .panelGlass(cornerRadius: 12)
    }

    @ViewBuilder private var setup: some View {
        Picker("格式", selection: $model.options.format) {
            ForEach(RecordingFormat.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .frame(width: 104)
        audioToggle("speaker.wave.2.fill", off: "speaker.slash", isOn: $model.options.systemAudio, help: "录系统声音")
        audioToggle("mic.fill", off: "mic.slash", isOn: $model.options.microphone, help: "录麦克风")
        Text(model.message ?? model.sizeText)
            .font(.caption.monospacedDigit())
            .foregroundStyle(model.message == nil ? Color.secondary : Color.orange)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
        Button { model.cancel() } label: { Text("取消").frame(width: Self.buttonWidth - 20) }
            .help("Esc")
        Button { model.start() } label: { Text("开始录制").frame(width: Self.buttonWidth - 20) }
            .buttonStyle(.borderedProminent)
            .help("⏎")
    }

    /// 自己画的开关按钮：开 / 关只换图标和底色，宽度不变。GIF 没有声音，按钮变灰
    private func audioToggle(_ symbol: String, off: String, isOn: Binding<Bool>, help: String) -> some View {
        let enabled = model.options.format == .mp4
        let active = isOn.wrappedValue && enabled
        return Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: active ? symbol : off)
                .font(.system(size: 13))
                .foregroundStyle(active ? Color.white : Color.secondary)
                .frame(width: 30, height: 24)
                .background(active ? Color.accentColor : Color.primary.opacity(0.08), in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(enabled ? help : "GIF 不录声音")
    }

    @ViewBuilder private var recording: some View {
        Circle().fill(.red).frame(width: 9, height: 9)
        Text(model.elapsedText)
            .font(.callout.monospacedDigit())
            .frame(width: 48, alignment: .leading)
        Text(model.options.format.title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 32, alignment: .leading)
        HStack(spacing: 4) {
            if model.options.recordsAudio, model.options.systemAudio {
                Image(systemName: "speaker.wave.2.fill")
            }
            if model.options.recordsAudio, model.options.microphone {
                Image(systemName: "mic.fill")
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: 44, alignment: .leading)
        Spacer(minLength: 0)
        Button { model.cancel() } label: { Text("放弃").frame(width: Self.buttonWidth - 20) }
            .help("停止录制并删除文件")
        Button { model.stop() } label: {
            Label("完成", systemImage: "stop.fill").frame(width: Self.buttonWidth - 20)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .help("停止录制并保存（再按一次录屏快捷键也可以）")
    }
}

/// 选区外的虚线边框 + 控制条。都是 MAIO 的窗口，录屏时被排除，不会录进去
@MainActor
final class RecordingFrame {
    private let border: NSPanel
    private let bar: NSPanel

    /// rect：全局坐标（左上角原点，pt）
    init(rect: CGRect, model: RecordingModel) {
        border = FloatingPanels.border(around: rect)
        bar = FloatingPanels.make(frame: Self.barFrame(for: FloatingPanels.appKitRect(rect)))
        let hosting = NSHostingView(rootView: RecordingBar(model: model))
        // 面板大小固定，不随内容变化
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: RecordingBar.size)
        bar.contentView = hosting
    }

    func show() {
        border.orderFrontRegardless()
        bar.orderFrontRegardless()
    }

    /// 录制中边框变红
    func setRecording(_ recording: Bool) {
        (border.contentView as? DashedBorderView)?.color = recording ? .systemRed : .controlAccentColor
    }

    func close() {
        border.close()
        bar.close()
    }

    /// 选区下方居中；下方放不下放上方，都放不下放在选区里靠下
    private static func barFrame(for selection: CGRect) -> CGRect {
        let visible = FloatingPanels.visibleFrame(containing: selection)
        let size = RecordingBar.size
        let gap: CGFloat = 8
        let y: CGFloat = if selection.minY - gap - size.height >= visible.minY {
            selection.minY - gap - size.height
        } else if selection.maxY + gap + size.height <= visible.maxY {
            selection.maxY + gap
        } else {
            max(visible.minY, selection.minY) + gap
        }
        let x = min(max(selection.midX - size.width / 2, visible.minX + gap), visible.maxX - size.width - gap)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
