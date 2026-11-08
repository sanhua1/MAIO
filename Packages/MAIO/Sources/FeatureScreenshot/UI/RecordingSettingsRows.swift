import AppKit
import MAIOUI
import SwiftUI

/// 截图设置里的「录屏」部分（ADR-0024）
struct RecordingSettingsRows: View {
    @Binding var value: ScreenshotSettings

    var body: some View {
        LabeledContent {
            Text("⌥F3 或截图时 ⌘R · 录制中再按 ⌥F3 结束").font(.caption).foregroundStyle(.secondary)
        } label: {
            LabelWithInfo("录屏", info: RecordingHelp.overview)
        }
        LabeledContent {
            HStack {
                Text(value.recordDirectory.isEmpty ? "~/Movies/MAIO" : value.recordDirectory)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("选择…") { chooseDirectory() }
                if !value.recordDirectory.isEmpty {
                    Button("恢复默认") { value.recordDirectory = "" }
                }
            }
        } label: {
            Text("录屏保存文件夹")
        }
        Picker(selection: $value.videoCodec) {
            ForEach(VideoCodec.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
            LabelWithInfo("MP4 编码", info: RecordingHelp.codec)
        }
        Picker("MP4 帧率", selection: $value.videoFrameRate) {
            ForEach(RecordingOptions.videoFrameRates, id: \.self) { Text("\($0) 帧/秒").tag($0) }
        }
        Picker("GIF 帧率", selection: $value.gifFrameRate) {
            ForEach(RecordingOptions.gifFrameRates, id: \.self) { Text("\($0) 帧/秒").tag($0) }
        }
        Toggle(isOn: $value.gifHighResolution) {
            LabelWithInfo("GIF 按 Retina 清晰度录制", info: RecordingHelp.gifResolution)
        }
        Toggle("录制鼠标指针", isOn: $value.recordShowsCursor)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            value.recordDirectory = url.path
        }
    }
}

enum RecordingHelp {
    static let overview = """
    框选区域后，在下方的控制条上选 MP4 或 GIF；MP4 可以同时录系统声音和麦克风（混成一条音轨）。⏎ 或「开始录制」开始，Esc 取消。
    录制中按键照常打到其他 App，用控制条上的「完成」或再按一次录屏快捷键结束；「放弃」删除文件。
    录完保存到录屏文件夹，并把文件复制到剪贴板，可以直接粘贴到访达、微信、邮件。MAIO 自己的窗口和声音不会被录进去。
    """
    static let codec = "H.264 几乎所有地方都能播放；HEVC 同样清晰度文件小约 40%，但部分 Windows 电脑和网页播放不了。两种都用硬件编码，CPU 占用很低。"
    static let gifResolution = "默认按屏幕的点（pt）录 GIF，文件约小 4 倍，编码也快很多。打开后按 Retina 像素录，文字更锐利。"
}
