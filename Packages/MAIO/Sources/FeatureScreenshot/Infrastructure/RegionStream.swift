import CoreMedia
import Foundation
import os
import ScreenCaptureKit
import VideoToolbox

/// 长截图的取帧：对选区开一个 ScreenCaptureKit 视频流（思路参考 Snow Shot：视频流 + 只留最新一帧的信箱）。
/// - 只在画面有变化时才收到新帧（系统会跳过没变化的帧）；
/// - 处理不过来时只保留最新的一帧，旧的直接丢掉，不会越积越多；
/// - 排除 MAIO 自己的窗口（边框、右侧面板放在选区里也不会被截进去）。
final class RegionStream: NSObject, SCStreamOutput, @unchecked Sendable {
    private let stream: SCStream
    private let queue = DispatchQueue(label: "maio.screenshot.scroll-stream", qos: .userInitiated)
    private let latest = OSAllocatedUnfairLock<CGImage?>(initialState: nil)

    private init(filter: SCContentFilter, configuration: SCStreamConfiguration) {
        stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
    }

    /// rect：全局坐标（左上角原点，pt）；display：rect 所在的显示器
    static func start(rect: CGRect, display: DisplayInfo, scale: CGFloat) async throws -> RegionStream {
        let source = try await withTimeout(ScreenCapturer.timeout) {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let screen = content.displays.first(where: { $0.displayID == display.id }) else {
                throw CaptureError.noImage
            }
            let own = content.applications.filter { $0.processID == getpid() }
            let filter = SCContentFilter(display: screen, excludingApplications: own, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = rect.offsetBy(dx: -display.bounds.minX, dy: -display.bounds.minY)
            configuration.width = Int((rect.width * scale).rounded())
            configuration.height = Int((rect.height * scale).rounded())
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.queueDepth = 4
            configuration.showsCursor = false
            configuration.captureResolution = .best
            return RegionStream(filter: filter, configuration: configuration)
        }
        try source.stream.addStreamOutput(source, type: .screen, sampleHandlerQueue: source.queue)
        try await withTimeout(ScreenCapturer.timeout) { try await source.stream.startCapture() }
        return source
    }

    func stop() async {
        try? await stream.stopCapture()
    }

    /// 取走最新的一帧（没有新帧时返回 nil）
    func take() -> CGImage? {
        latest.withLock { value in
            defer { value = nil }
            return value
        }
    }

    func stream(_: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, Self.isComplete(buffer), let pixels = buffer.imageBuffer else { return }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image)
        guard let image else { return }
        latest.withLock { $0 = image }
    }

    /// 只要内容完整的帧（idle、blank 等状态的帧没有新画面）
    private static func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int else { return false }
        return SCFrameStatus(rawValue: raw) == .complete
    }
}
