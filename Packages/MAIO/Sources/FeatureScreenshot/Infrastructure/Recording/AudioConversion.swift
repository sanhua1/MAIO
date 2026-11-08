import AVFoundation
import CoreMedia

/// 把一个来源的声音转成 48 kHz、浮点、按声道分开的立体声采样（混音前统一格式）。
/// 系统声音本来就是这个格式（流配置里指定了），直接拷贝；麦克风的格式取决于设备，必要时重采样。
final class AudioNormalizer {
    private var converter: AVAudioConverter?
    private var converterInput: AVAudioFormat?

    /// 返回每个声道一组采样（单声道时复制成两个声道）
    func samples(from buffer: CMSampleBuffer) -> [[Float]]? {
        guard let description = buffer.formatDescription else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(buffer))
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            buffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList,
        )
        guard status == noErr else { return nil }
        let converted = format.commonFormat == .pcmFormatFloat32 && !format.isInterleaved
            && format.sampleRate == Double(AudioFormat.sampleRate) ? pcm : convert(pcm)
        guard let converted, let channels = converted.floatChannelData else { return nil }
        let count = Int(converted.frameLength)
        let channelCount = Int(converted.format.channelCount)
        let output = (0 ..< min(channelCount, AudioFormat.channels)).map { channel in
            Array(UnsafeBufferPointer(start: channels[channel], count: count))
        }
        return output.count == 1 ? [output[0], output[0]] : output
    }

    /// 重采样 / 转成浮点（保留声道数，最多两个声道）
    private func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let channels = min(input.format.channelCount, AVAudioChannelCount(AudioFormat.channels))
        guard let output = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioFormat.sampleRate), channels: channels,
            interleaved: false,
        ) else { return nil }
        if converter == nil || converterInput != input.format || converter?.outputFormat != output {
            converter = AVAudioConverter(from: input.format, to: output)
            converterInput = input.format
        }
        guard let converter else { return nil }
        let ratio = output.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 32
        guard let result = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: result, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        return error == nil ? result : nil
    }
}

/// 混好的采样 → 可以交给 AVAssetWriter 的 CMSampleBuffer
enum AudioSampleBuffer {
    static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioFormat.sampleRate),
        channels: AVAudioChannelCount(AudioFormat.channels), interleaved: false,
    )

    static func make(_ samples: [[Float]], presentationTime: CMTime) -> CMSampleBuffer? {
        guard let format, let length = samples.first?.count, length > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length)),
              let channels = pcm.floatChannelData else { return nil }
        pcm.frameLength = AVAudioFrameCount(length)
        for (index, channel) in samples.prefix(Int(format.channelCount)).enumerated() {
            channel.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                channels[index].update(from: base, count: length)
            }
        }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(AudioFormat.sampleRate)),
            presentationTimeStamp: presentationTime, decodeTimeStamp: .invalid,
        )
        var buffer: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil,
            refcon: nil, formatDescription: format.formatDescription, sampleCount: CMItemCount(length),
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &buffer,
        ) == noErr, let buffer else { return nil }
        let status = CMSampleBufferSetDataBufferFromAudioBufferList(
            buffer, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, bufferList: pcm.audioBufferList,
        )
        return status == noErr ? buffer : nil
    }
}
