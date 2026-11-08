import CoreMedia
import Foundation
import os
import ScreenCaptureKit

/// 收录屏数据的一方（MP4 / GIF 写入器）。所有回调都在同一个串行队列上，不用加锁
protocol RecordingSink: AnyObject, Sendable {
    /// 录屏流在这个串行队列上回调
    var queue: DispatchQueue { get }
    func appendVideo(_ buffer: CMSampleBuffer)
    /// time：这段声音的时刻（主机时钟）
    func appendAudio(_ buffer: CMSampleBuffer, source: AudioSource, at time: CMTime)
}

enum AudioSource: Int, Sendable {
    case system
    case microphone
}

/// 对选区开一个 ScreenCaptureKit 流（ADR-0024）：
/// - 画面、系统声音由同一个流提供；麦克风另外直接从设备采集（见 MicrophoneCapture），时间戳都在主机时钟上；
/// - 画面没变化时系统不发新帧（可变帧率），静止画面几乎不耗 CPU；
/// - MP4 直接要 4:2:0 YUV，交给硬件编码器时不用转换；GIF 要 BGRA；
/// - 排除 MAIO 自己的窗口和声音（录制控制条、边框不会被录进去）。
final class ScreenRecorder: NSObject, SCStreamOutput, @unchecked Sendable {
    struct Request: Sendable {
        /// 全局坐标（左上角原点，pt）
        let rect: CGRect
        let display: DisplayInfo
        let size: RecordingGeometry.PixelSize
        let options: RecordingOptions
    }

    private let stream: SCStream
    private let sink: any RecordingSink
    private let monitor: StopMonitor
    private var microphone: MicrophoneCapture?

    private init(
        filter: SCContentFilter, configuration: SCStreamConfiguration, sink: any RecordingSink,
        onError: @escaping @Sendable (any Error) -> Void,
    ) {
        self.sink = sink
        monitor = StopMonitor(onError)
        stream = SCStream(filter: filter, configuration: configuration, delegate: monitor)
        super.init()
    }

    /// onError：流被系统意外停止（显示器休眠、权限被收回等）
    static func start(
        _ request: Request, sink: any RecordingSink, onError: @escaping @Sendable (any Error) -> Void,
    ) async throws -> ScreenRecorder {
        let recorder = try await withTimeout(ScreenCapturer.timeout) {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let screen = content.displays.first(where: { $0.displayID == request.display.id }) else {
                throw CaptureError.noImage
            }
            let own = content.applications.filter { $0.processID == getpid() }
            let filter = SCContentFilter(display: screen, excludingApplications: own, exceptingWindows: [])
            return ScreenRecorder(filter: filter, configuration: configuration(for: request), sink: sink, onError: onError)
        }
        try recorder.attach(request.options)
        if request.options.format == .mp4, request.options.microphone {
            let microphone = try MicrophoneCapture(sink: sink)
            await Task.detached(priority: .userInitiated) { microphone.start() }.value
            recorder.microphone = microphone
        }
        do {
            try await withTimeout(ScreenCapturer.timeout) { try await recorder.stream.startCapture() }
        } catch {
            recorder.microphone?.stop()
            throw error
        }
        return recorder
    }

    private static func configuration(for request: Request) -> SCStreamConfiguration {
        let options = request.options
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = request.rect.offsetBy(dx: -request.display.bounds.minX, dy: -request.display.bounds.minY)
        configuration.width = request.size.width
        configuration.height = request.size.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.frameRate))
        configuration.queueDepth = 6
        configuration.showsCursor = options.showsCursor
        configuration.scalesToFit = true
        if options.format == .mp4 {
            configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            configuration.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        } else {
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
        }
        configuration.colorSpaceName = CGColorSpace.sRGB
        if options.format == .mp4, options.systemAudio {
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = AudioFormat.sampleRate
            configuration.channelCount = AudioFormat.channels
        }
        return configuration
    }

    private func attach(_ options: RecordingOptions) throws {
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sink.queue)
        if options.format == .mp4, options.systemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sink.queue)
        }
    }

    func stop() async {
        monitor.disarm()
        microphone?.stop()
        try? await stream.stopCapture()
    }

    // MARK: SCStreamOutput

    func stream(_: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard buffer.isValid else { return }
        switch type {
        case .screen:
            if Self.isComplete(buffer) {
                sink.appendVideo(buffer)
            }
        case .audio:
            sink.appendAudio(buffer, source: .system, at: buffer.presentationTimeStamp)
        case .microphone:
            // 不用流的麦克风（会混进系统声音），见 MicrophoneCapture
            break
        @unknown default:
            break
        }
    }

    /// 只要内容完整的帧（idle 帧没有新画面）
    private static func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int else { return false }
        return SCFrameStatus(rawValue: raw) == .complete
    }
}

/// 流被系统意外停止时通知一次；主动停止前先解除
private final class StopMonitor: NSObject, SCStreamDelegate, @unchecked Sendable {
    private let handler: OSAllocatedUnfairLock<(@Sendable (any Error) -> Void)?>

    init(_ handler: @escaping @Sendable (any Error) -> Void) {
        self.handler = OSAllocatedUnfairLock(initialState: handler)
    }

    func disarm() {
        handler.withLock { $0 = nil }
    }

    func stream(_: SCStream, didStopWithError error: any Error) {
        let handler = handler.withLock { value in
            defer { value = nil }
            return value
        }
        handler?(error)
    }
}

/// 混音后统一的声音格式
enum AudioFormat {
    static let sampleRate = 48000
    static let channels = 2
}
