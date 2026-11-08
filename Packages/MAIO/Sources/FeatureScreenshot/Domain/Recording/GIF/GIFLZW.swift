import Foundation

/// GIF 的 LZW 压缩（变长码，最长 12 位，码表满了发清除码）。
/// 码表用 8192 格的开放寻址表（键 = 前缀码 << 8 | 字节），清空只要重置 32 KB，比 4096×256 的树快得多。
/// 码长增长的时机和解码器严格对齐：解码器读到每个码（清除码后的第一个除外）都会登记一个新码，
/// 编码器总是比它早一步登记，所以结束前要替解码器补上最后一次登记再写结束码。
enum GIFLZW {
    static func encode(_ indices: [UInt8], minimumCodeSize: Int) -> [UInt8] {
        var state = State(minimumCodeSize: minimumCodeSize, capacity: indices.count / 2 + 16)
        guard let first = indices.first else {
            state.writer.write(state.end, size: state.codeSize)
            return state.writer.finish()
        }
        var current = Int(first)
        // 码表放在 State 外面：遍历时要同时持有码表指针和修改 State
        var keys = [Int32](repeating: -1, count: State.tableSize)
        var codes = [UInt16](repeating: 0, count: State.tableSize)
        keys.withUnsafeMutableBufferPointer { keys in
            codes.withUnsafeMutableBufferPointer { codes in
                for index in indices.dropFirst() {
                    let key = Int32(current << 8 | Int(index))
                    var slot = Int((UInt32(bitPattern: key) &* 2_654_435_761) >> 19)
                    while keys[slot] != -1, keys[slot] != key {
                        slot = (slot + 1) & (State.tableSize - 1)
                    }
                    if keys[slot] == key {
                        current = Int(codes[slot])
                        continue
                    }
                    if let code = state.emit(current) {
                        keys[slot] = key
                        codes[slot] = UInt16(code)
                    } else {
                        keys.update(repeating: -1)
                    }
                    current = Int(index)
                }
            }
        }
        state.finish(current)
        return state.writer.finish()
    }

    private struct State {
        static let tableSize = 8192
        static let maximumCode = 4095

        let minimumCodeSize: Int
        let clear: Int
        let end: Int
        var codeSize: Int
        var lastCode: Int
        var justCleared = true
        var writer = BitWriter()

        init(minimumCodeSize: Int, capacity: Int) {
            self.minimumCodeSize = minimumCodeSize
            clear = 1 << minimumCodeSize
            end = clear + 1
            codeSize = minimumCodeSize + 1
            lastCode = end
            writer.bytes.reserveCapacity(capacity)
            writer.write(clear, size: codeSize)
        }

        /// 写出当前前缀的码并登记新码，返回新码；码表满了就发清除码并返回 nil（调用方清空码表）
        mutating func emit(_ code: Int) -> Int? {
            writer.write(code, size: codeSize)
            justCleared = false
            lastCode += 1
            if lastCode >= 1 << codeSize {
                codeSize += 1
            }
            guard lastCode == Self.maximumCode else { return lastCode }
            writer.write(clear, size: codeSize)
            codeSize = minimumCodeSize + 1
            lastCode = end
            justCleared = true
            return nil
        }

        mutating func finish(_ code: Int) {
            writer.write(code, size: codeSize)
            // 解码器读到这个码时也会登记一个码，可能因此加长码长
            if !justCleared, lastCode + 1 >= 1 << codeSize, codeSize < 12 {
                codeSize += 1
            }
            writer.write(end, size: codeSize)
        }
    }

    /// 低位在前的位流
    private struct BitWriter {
        var bytes: [UInt8] = []
        private var accumulator: UInt32 = 0
        private var pendingBits = 0

        mutating func write(_ code: Int, size: Int) {
            accumulator |= UInt32(code) << UInt32(pendingBits)
            pendingBits += size
            while pendingBits >= 8 {
                bytes.append(UInt8(truncatingIfNeeded: accumulator))
                accumulator >>= 8
                pendingBits -= 8
            }
        }

        mutating func finish() -> [UInt8] {
            if pendingBits > 0 {
                bytes.append(UInt8(truncatingIfNeeded: accumulator))
            }
            return bytes
        }
    }
}
