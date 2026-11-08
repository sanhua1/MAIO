import CoreGraphics
import Foundation

/// 录屏的输出格式（ADR-0024）
enum RecordingFormat: String, Codable, CaseIterable, Sendable {
    case mp4
    case gif

    var title: String {
        switch self {
        case .mp4: "MP4"
        case .gif: "GIF"
        }
    }

    var fileExtension: String {
        rawValue
    }
}

/// MP4 的视频编码，都走硬件编码器
enum VideoCodec: String, Codable, CaseIterable, Sendable {
    /// 兼容性最好（微信、网页、Windows 都能直接播）
    case h264
    /// 同样清晰度文件小约 40%，部分 Windows 电脑和网页播放不了
    case hevc

    var title: String {
        switch self {
        case .h264: "H.264（兼容性最好）"
        case .hevc: "HEVC / H.265（文件更小）"
        }
    }

    /// 硬件编码器能接受的最大尺寸：H.264 Level 5.2 一帧最多 4096×2304 个像素，HEVC 8192×4320
    var maximumSide: Int {
        self == .h264 ? 4096 : 8192
    }

    var maximumArea: Int {
        self == .h264 ? 4096 * 2304 : 8192 * 4320
    }

    /// 每个像素每帧分到的码率（屏幕内容大部分是静止的文字和界面，这个值足够清楚）
    var bitsPerPixel: Double {
        self == .h264 ? 0.12 : 0.08
    }
}

/// 录屏参数（开始时从设置拷贝一份，录制中不变）
struct RecordingOptions: Equatable, Sendable {
    var format = RecordingFormat.mp4
    var codec = VideoCodec.h264
    var videoFrameRate = 30
    var gifFrameRate = 15
    /// GIF 按 Retina 像素录（默认按 pt 录：文件小 4 倍，编码快 4 倍）
    var gifHighResolution = false
    var showsCursor = true
    var systemAudio = false
    var microphone = false

    static let videoFrameRates = [24, 30, 60]
    /// GIF 的帧间隔以 1/100 秒为单位，而且很多播放器把小于 2/100 秒的间隔当成 1/10 秒，所以最高 30 帧
    static let gifFrameRates = [10, 15, 20, 25, 30]

    var frameRate: Int {
        format == .mp4 ? videoFrameRate : gifFrameRate
    }

    /// 只有 MP4 录声音
    var recordsAudio: Bool {
        format == .mp4 && (systemAudio || microphone)
    }
}

/// 录屏的像素尺寸与码率（纯计算，便于单测）
enum RecordingGeometry {
    struct PixelSize: Equatable, Sendable {
        let width: Int
        let height: Int
    }

    /// 输出的像素尺寸：
    /// - MP4 按 Retina 像素录，超过硬件编码器上限时等比缩小；宽高取偶数（4:2:0 色度要求）；
    /// - GIF 默认按 pt 录（scale 取 1），高清模式按 Retina 像素。
    static func outputSize(points: CGSize, scale: CGFloat, options: RecordingOptions) -> PixelSize {
        let pixelScale = options.format == .gif && !options.gifHighResolution ? 1 : max(scale, 1)
        var width = Double(points.width * pixelScale)
        var height = Double(points.height * pixelScale)
        if options.format == .mp4 {
            let side = Double(options.codec.maximumSide)
            let area = Double(options.codec.maximumArea)
            let shrink = min(1, side / max(width, 1), side / max(height, 1), (area / max(width * height, 1)).squareRoot())
            width *= shrink
            height *= shrink
            return PixelSize(width: max(2, Int(width / 2) * 2), height: max(2, Int(height / 2) * 2))
        }
        return PixelSize(width: max(1, Int(width.rounded())), height: max(1, Int(height.rounded())))
    }

    /// 平均码率（bit/s），限制在 2～60 Mbps
    static func bitRate(size: PixelSize, frameRate: Int, codec: VideoCodec) -> Int {
        let bits = Double(size.width * size.height * frameRate) * codec.bitsPerPixel
        return Int(min(60_000_000, max(2_000_000, bits)))
    }
}

/// 录屏文件名：`MAIO 2026-11-08 14.05.33.mp4`
enum RecordingFileName {
    static func make(date: Date, format: RecordingFormat, existing: (String) -> Bool) -> String {
        ScreenshotFileName.make(date: date, fileExtension: format.fileExtension, existing: existing)
    }
}
