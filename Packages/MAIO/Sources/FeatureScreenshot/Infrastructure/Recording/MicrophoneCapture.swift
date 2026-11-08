import AVFoundation
import CoreMedia

/// 直接从默认麦克风设备采集（AVCaptureSession），不用 ScreenCaptureKit 的 captureMicrophone：
/// 实测（2026-11-08，macOS 27）ScreenCaptureKit 给的麦克风数据里混进了系统声音——只开麦克风、
/// 戴耳机播放提示音，流里的峰值 0.33；同时直接读设备只有 0.05（耳机漏音）。
/// 时间戳换算到主机时钟，和录屏流的画面、系统声音在同一个时钟上。回调在 sink 的队列上。
final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let sink: any RecordingSink

    init(sink: any RecordingSink) throws {
        self.sink = sink
        super.init()
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw RecordingError.writer("没有找到麦克风")
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw RecordingError.writer("无法使用麦克风")
        }
        session.addInput(input)
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioFormat.sampleRate,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: true,
        ]
        output.setSampleBufferDelegate(self, queue: sink.queue)
        session.addOutput(output)
    }

    /// startRunning 会阻塞（打开设备），不要在主线程调用
    func start() {
        session.startRunning()
    }

    func stop() {
        output.setSampleBufferDelegate(nil, queue: nil)
        session.stopRunning()
    }

    func captureOutput(_: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from _: AVCaptureConnection) {
        var time = buffer.presentationTimeStamp
        let host = CMClockGetHostTimeClock()
        if let clock = session.synchronizationClock, clock != host {
            time = CMSyncConvertTime(time, from: clock, to: host)
        }
        sink.appendAudio(buffer, source: .microphone, at: time)
    }
}
