import Foundation
import IOKit
import Synchronization

// Apple Silicon 上外接显示器的 I2C（DDC）通道，私有 API（IOKit 导出，没有头文件）。
// 参考：references/MonitorControl/MonitorControl/Support/Arm64DDC.swift
@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(
    _ service: CFTypeRef, _ chipAddress: UInt32, _ offset: UInt32,
    _ buffer: UnsafeMutableRawPointer, _ size: UInt32,
) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(
    _ service: CFTypeRef, _ chipAddress: UInt32, _ dataAddress: UInt32,
    _ buffer: UnsafeMutableRawPointer, _ size: UInt32,
) -> IOReturn

/// 一台显示器的 DDC 通道。所有读写在同一个串行队列上排队（DDC 一次往返要几十毫秒）；
/// 写入会合并：按住按键连续调节时，只把每个功能码的最新值写下去。
final class DDCChannel: @unchecked Sendable {
    private let service: CFTypeRef
    private let queue = DispatchQueue(label: "app.maio.display.ddc", qos: .userInitiated)
    private struct Pending {
        var values: [VCPCode: Int] = [:]
        var isDraining = false
    }

    private let pending = Mutex(Pending())

    /// `entry` 是 IORegistry 里 Location = External 的 DCPAVServiceProxy
    init?(entry: io_service_t) {
        guard let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else {
            return nil
        }
        self.service = service
    }

    func read(_ code: VCPCode) async -> DDCReadResult {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: readNow(code))
            }
        }
    }

    func write(_ code: VCPCode, value: Int) {
        let shouldStart = pending.withLock { state in
            state.values[code] = value
            defer { state.isDraining = true }
            return !state.isDraining
        }
        guard shouldStart else { return }
        queue.async { [self] in drain() }
    }

    // MARK: 队列内

    private func drain() {
        while true {
            let next = pending.withLock { state -> (VCPCode, Int)? in
                guard let (code, value) = state.values.first else {
                    state.isDraining = false
                    return nil
                }
                state.values[code] = nil
                return (code, value)
            }
            guard let (code, value) = next else { return }
            writeNow(code, value: value)
        }
    }

    private func writeNow(_ code: VCPCode, value: Int) {
        var packet = DDCPacket.setRequest(code, value: value)
        // 写两遍：有的显示器偶尔丢包，写入没有回执（MonitorControl 默认也是两遍）
        for _ in 0 ..< 2 {
            usleep(10000)
            _ = send(&packet)
        }
    }

    private func readNow(_ code: VCPCode) -> DDCReadResult {
        for _ in 0 ..< 5 {
            var request = DDCPacket.getRequest(code)
            usleep(10000)
            if send(&request) {
                usleep(50000)
                var reply = [UInt8](repeating: 0, count: 11)
                let status = IOAVServiceReadI2C(
                    service, UInt32(DDCPacket.chipAddress), 0, &reply, UInt32(reply.count),
                )
                if status == kIOReturnSuccess {
                    let result = DDCPacket.parse(reply, for: code)
                    if result != .failed {
                        return result
                    }
                }
            }
            usleep(40000)
        }
        return .failed
    }

    private func send(_ packet: inout [UInt8]) -> Bool {
        IOAVServiceWriteI2C(
            service, UInt32(DDCPacket.chipAddress), UInt32(DDCPacket.dataAddress), &packet, UInt32(packet.count),
        ) == kIOReturnSuccess
    }
}
