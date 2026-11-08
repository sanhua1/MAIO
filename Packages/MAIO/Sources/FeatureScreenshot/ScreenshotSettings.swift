import MAIOKit

/// 设置项：字段只增不删；结构不兼容的修改要提升 schemaVersion 并实现 migrate。
struct ScreenshotSettings: FeatureSettings {
    static let defaultValue = ScreenshotSettings()
    /// 2：贴图缩放的默认修饰键从 ⌃ 改为不按修饰键（用户要求直接滚轮缩放）
    static let schemaVersion = 2

    static func migrate(_ json: inout JSONValue, from version: Int) throws {
        guard version < 2, case var .object(fields) = json, fields["pinZoomModifier"] == .string("control") else { return }
        fields["pinZoomModifier"] = .string("none")
        json = .object(fields)
    }

    /// 总是识别控件（关闭时按住 ⌘ 才识别控件，平时只识别窗口）
    var alwaysDetectControls = false
    var showMagnifier = true
    /// 取色的格式，截图时按 ⇧ 切换后会记住
    var colorFormat = ColorFormat.hex
    /// 保存文件夹，空表示默认的 ~/Pictures/MAIO
    var saveDirectory = ""
    /// ⌘S 时弹出"存储为"对话框
    var askSaveLocation = false
    /// 复制截图时也自动保存一份到保存文件夹
    var autoSave = false
    /// 截图历史的存储上限（用户选择默认 2 GB）
    var historyLimit = HistoryLimit.gb2
    /// 贴图默认显示主题色的发光阴影；关掉后是一张纯粹的图
    var pinShadow = true
    /// 贴图缩放：修饰键 + 滚轮（或 - =），默认不按修饰键（直接滚轮、直接按 - =）
    var pinZoomModifier = PinModifier.none
    /// 贴图透明度：修饰键 + 滚轮（或 - =），默认 ⌘
    var pinOpacityModifier = PinModifier.command

    var pinControls: PinControls {
        PinControls(zoomModifier: pinZoomModifier, opacityModifier: pinOpacityModifier)
    }

    /// 标注工具上次用过的颜色、大小、选项
    var toolStyle = ToolStyle()

    // MARK: 录屏（ADR-0024）

    /// 上次选的格式，开始录制前可以在控制条上改
    var recordFormat = RecordingFormat.mp4
    /// 录系统声音（只有 MP4）
    var recordSystemAudio = false
    /// 录麦克风（只有 MP4），和系统声音混成一条音轨
    var recordMicrophone = false
    var videoCodec = VideoCodec.h264
    var videoFrameRate = 30
    var gifFrameRate = 15
    /// GIF 按 Retina 像素录（默认按 pt：文件小、编码快）
    var gifHighResolution = false
    var recordShowsCursor = true
    /// 录屏保存文件夹，空表示默认的 ~/Movies/MAIO
    var recordDirectory = ""

    var recordingOptions: RecordingOptions {
        RecordingOptions(
            format: recordFormat, codec: videoCodec,
            videoFrameRate: RecordingOptions.videoFrameRates.contains(videoFrameRate) ? videoFrameRate : 30,
            gifFrameRate: RecordingOptions.gifFrameRates.contains(gifFrameRate) ? gifFrameRate : 15,
            gifHighResolution: gifHighResolution, showsCursor: recordShowsCursor,
            systemAudio: recordSystemAudio, microphone: recordMicrophone,
        )
    }

    /// 控制条上改的格式和声音开关记下来，下次默认
    mutating func remember(_ options: RecordingOptions) {
        recordFormat = options.format
        recordSystemAudio = options.systemAudio
        recordMicrophone = options.microphone
    }
}
