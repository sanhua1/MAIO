import AVFoundation
import CoreMedia

enum RecordingError: LocalizedError {
    case noFrames
    case writer(String)

    var errorDescription: String? {
        switch self {
        case .noFrames: "没有录到画面"
        case let .writer(message): message
        }
    }
}

/// MP4 写入（ADR-0024）：录屏流给的 YUV 帧原样交给 AVAssetWriter 的硬件编码器（不拷贝、不转换）；
/// 系统声音和麦克风按时间戳混成一条 AAC 音轨。所有方法都在 queue 上执行。
final class MovieWriter: RecordingSink, @unchecked Sendable {
    let queue = DispatchQueue(label: "maio.screenshot.recording", qos: .userInitiated)
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput?
    /// 某一路没声音时最多等 0.2 秒；相邻两段之间 2 毫秒以内的缝隙当作连续
    private var mixer: AudioMixer
    private var normalizers: [AudioSource: AudioNormalizer] = [:]
    private var startTime: CMTime?
    private var lastVideoTime = CMTime.zero

    init(url: URL, size: RecordingGeometry.PixelSize, options: RecordingOptions) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(size: size, options: options))
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw RecordingError.writer("视频编码器不支持这个尺寸") }
        writer.add(video)
        let sources = (options.systemAudio ? [AudioSource.system] : []) + (options.microphone ? [.microphone] : [])
        mixer = AudioMixer(
            sources: sources.map(\.rawValue), latency: AudioFormat.sampleRate / 5, tolerance: AudioFormat.sampleRate / 500,
        )
        if options.recordsAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw RecordingError.writer("无法添加音轨") }
            writer.add(input)
            audio = input
        } else {
            audio = nil
        }
    }

    private static func videoSettings(size: RecordingGeometry.PixelSize, options: RecordingOptions) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: RecordingGeometry.bitRate(
                size: size, frameRate: options.videoFrameRate, codec: options.codec,
            ),
            AVVideoExpectedSourceFrameRateKey: options.videoFrameRate,
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
            // 不用 B 帧：编码延迟低、占内存少
            AVVideoAllowFrameReorderingKey: false,
        ]
        if options.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        return [
            AVVideoCodecKey: options.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: compression,
        ]
    }

    private static var audioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: AudioFormat.sampleRate,
            AVNumberOfChannelsKey: AudioFormat.channels,
            AVEncoderBitRateKey: 160_000,
        ]
    }

    // MARK: RecordingSink

    func appendVideo(_ buffer: CMSampleBuffer) {
        let time = buffer.presentationTimeStamp
        if startTime == nil {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: time)
            startTime = time
        }
        guard writer.status == .writing, video.isReadyForMoreMediaData, time > lastVideoTime else { return }
        if video.append(buffer) {
            lastVideoTime = time
        }
    }

    func appendAudio(_ buffer: CMSampleBuffer, source: AudioSource, at time: CMTime) {
        guard audio != nil, let startTime else { return }
        let normalizer = normalizers[source] ?? AudioNormalizer()
        normalizers[source] = normalizer
        guard let samples = normalizer.samples(from: buffer) else { return }
        let offset = (time - startTime).seconds
        mixer.push(source: source.rawValue, at: Int((offset * Double(AudioFormat.sampleRate)).rounded()), samples: samples)
        drainAudio(flush: false)
    }

    private func drainAudio(flush: Bool) {
        guard let audio, let startTime else { return }
        while true {
            let position = mixer.emitted
            guard let mixed = mixer.pull(flush: flush) else { return }
            let time = startTime + CMTime(value: CMTimeValue(position), timescale: CMTimeScale(AudioFormat.sampleRate))
            // 编码器忙不过来时丢掉这一段（实时录制不能等）
            guard writer.status == .writing, audio.isReadyForMoreMediaData,
                  let sample = AudioSampleBuffer.make(mixed, presentationTime: time) else { continue }
            audio.append(sample)
        }
    }

    // MARK: 结束

    /// 录制流停止之后调用。end：结束时刻（主机时钟），最后一帧显示到这里
    func finish(at end: CMTime) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                guard startTime != nil, writer.status == .writing else {
                    writer.cancelWriting()
                    continuation.resume(throwing: writer.error ?? RecordingError.noFrames)
                    return
                }
                drainAudio(flush: true)
                video.markAsFinished()
                audio?.markAsFinished()
                writer.endSession(atSourceTime: max(end, lastVideoTime))
                writer.finishWriting { [self] in
                    if writer.status == .completed {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: writer.error ?? RecordingError.writer("写入视频失败"))
                    }
                }
            }
        }
    }

    func discard() {
        queue.async { [self] in
            if writer.status == .writing {
                writer.cancelWriting()
            }
        }
    }
}
