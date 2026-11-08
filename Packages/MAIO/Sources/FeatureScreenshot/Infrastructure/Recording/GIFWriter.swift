import CoreMedia
import CoreVideo
import Foundation
import os

/// GIF 写入（ADR-0024）：边录边编，编好一帧立即写盘，内存里只留上一帧的像素和一帧待写的数据。
/// - 录屏流的回调只把最新一帧放进信箱（不做任何计算），编码在单独的低优先级队列上；
/// - 编码跟不上时中间帧直接丢掉，丢掉的时间算进上一帧的显示时长，播放速度不变；
/// - 一帧的显示时长要等下一帧到了才知道，所以总是晚一帧写。
final class GIFWriter: RecordingSink, @unchecked Sendable {
    let queue = DispatchQueue(label: "maio.screenshot.recording", qos: .userInitiated)
    private let encodeQueue = DispatchQueue(label: "maio.screenshot.gif-encode", qos: .utility)

    /// 像素缓冲只在信箱和编码队列之间交接，同一时刻只有一方持有
    private struct Incoming: @unchecked Sendable {
        let pixels: CVPixelBuffer
        let time: Double
    }

    /// 信箱：最新一帧；scheduled 表示编码队列上已经排了一次处理
    private let mailbox = OSAllocatedUnfairLock<(frame: Incoming?, scheduled: Bool)>(initialState: (nil, false))

    // 以下只在 encodeQueue 上访问
    private var encoder: GIFFrameEncoder
    private let file: FileHandle
    private var startTime: Double?
    private var pending: (frame: GIFFrame, time: Double)?
    private var failure: (any Error)?

    init(url: URL, size: RecordingGeometry.PixelSize) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: GIFFormat.header(width: size.width, height: size.height))
        else { throw RecordingError.writer("无法创建 GIF 文件") }
        file = try FileHandle(forWritingTo: url)
        try file.seekToEnd()
        encoder = GIFFrameEncoder(width: size.width, height: size.height)
    }

    // MARK: RecordingSink

    func appendVideo(_ buffer: CMSampleBuffer) {
        guard let pixels = buffer.imageBuffer else { return }
        let incoming = Incoming(pixels: pixels, time: buffer.presentationTimeStamp.seconds)
        let schedule = mailbox.withLock { state in
            state.frame = incoming
            defer { state.scheduled = true }
            return !state.scheduled
        }
        if schedule {
            encodeQueue.async { [self] in drain() }
        }
    }

    func appendAudio(_: CMSampleBuffer, source _: AudioSource, at _: CMTime) {}

    // MARK: 编码

    private func drain() {
        while let incoming = mailbox.withLock({ state -> Incoming? in
            defer { state.frame = nil }
            if state.frame == nil {
                state.scheduled = false
            }
            return state.frame
        }) {
            encode(incoming)
        }
    }

    private func encode(_ incoming: Incoming) {
        guard failure == nil, let pixels = Self.copyPixels(incoming.pixels, width: encoder.width, height: encoder.height)
        else { return }
        let start = startTime ?? incoming.time
        startTime = start
        guard let frame = encoder.encode(pixels) else { return }
        let time = incoming.time - start
        write(until: time)
        pending = (frame, time)
    }

    /// 把待写的那一帧写盘，显示到 time
    private func write(until time: Double) {
        guard let pending else { return }
        self.pending = nil
        do {
            try file.write(contentsOf: GIFFormat.frame(pending.frame, delay: GIFFormat.delay(from: pending.time, to: time)))
        } catch {
            failure = error
        }
    }

    /// BGRA 像素拷成连续的 UInt32（去掉行尾填充），拷完就把缓冲还给录屏流
    private static func copyPixels(_ buffer: CVPixelBuffer, width: Int, height: Int) -> [UInt32]? {
        guard CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        return [UInt32](unsafeUninitializedCapacity: width * height) { output, count in
            guard let target = output.baseAddress else { return }
            for row in 0 ..< height {
                memcpy(target + row * width, base + row * rowBytes, width * MemoryLayout<UInt32>.size)
            }
            count = width * height
        }
    }

    // MARK: 结束

    /// 录制流停止之后调用：编完信箱里剩下的帧，最后一帧显示到 end（主机时钟，秒）
    func finish(at end: Double) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            encodeQueue.async { [self] in
                drain()
                guard let startTime, pending != nil else {
                    try? file.close()
                    continuation.resume(throwing: failure ?? RecordingError.noFrames)
                    return
                }
                write(until: max(end - startTime, (pending?.time ?? 0) + 0.02))
                do {
                    try file.write(contentsOf: GIFFormat.trailer)
                    try file.close()
                } catch {
                    failure = failure ?? error
                }
                if let failure {
                    continuation.resume(throwing: failure)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func discard() {
        encodeQueue.async { [file] in try? file.close() }
    }
}
