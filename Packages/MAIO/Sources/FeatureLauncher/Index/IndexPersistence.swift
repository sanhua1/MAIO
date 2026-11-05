import Foundation

// 参考：references/oil-find/Sources/OilFindCore/IndexStore+Persistence.swift（MIT）
/// 索引存盘：`data/launcher/index.bin`。文件头 + 各数组原样写出（先写临时文件再改名）。
/// 哈希表不存，读盘后重建。
enum IndexPersistence {
    static let magic = Array("MAIOIDX1".utf8)
    static let version: UInt32 = 1

    /// 和索引一起保存的状态。任何一项和当前不一致，就不能接着用这份索引
    struct Header: Equatable {
        /// 扫描设置的指纹（排除目录、是否索引包内部……变了就要重扫）
        var optionsHash: UInt64
        /// 存盘时处理到的 FSEvents 事件编号，下次从这里回放
        var lastEventID: UInt64
        /// FSEvents 事件库的 UUID（系统重建事件库后编号作废）
        var eventStoreUUID: String
        var savedAt: UInt64
    }

    enum Failure: Error {
        case badFormat
    }

    static func save(_ data: IndexData, header: Header, to url: URL) throws {
        var writer = BinaryWriter()
        writer.bytes(magic)
        writer.value(version)
        writer.value(header.optionsHash)
        writer.value(header.lastEventID)
        writer.string(header.eventStoreUUID)
        writer.value(header.savedAt)
        writer.array(data.parents)
        writer.array(data.flags)
        writer.array(data.depths)
        writer.array(data.sizes)
        writer.array(data.mtimes)
        writer.array(data.folded)
        writer.array(data.nameStart)
        writer.array(data.rawStart)
        writer.array(data.raw)
        writer.array(data.altKeys)
        writer.array(data.altStart)
        writer.array(data.altOwner)
        let temporary = url.appendingPathExtension("tmp")
        try writer.data.write(to: temporary)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    static func load(from url: URL) throws -> (header: Header, data: IndexData) {
        var reader = try BinaryReader(Data(contentsOf: url, options: .alwaysMapped))
        guard try reader.bytes(magic.count) == magic, try reader.value(UInt32.self) == version else {
            throw Failure.badFormat
        }
        let header = try Header(
            optionsHash: reader.value(UInt64.self), lastEventID: reader.value(UInt64.self),
            eventStoreUUID: reader.string(), savedAt: reader.value(UInt64.self),
        )
        var data = IndexData()
        data.parents = try reader.array()
        data.flags = try reader.array()
        data.depths = try reader.array()
        data.sizes = try reader.array()
        data.mtimes = try reader.array()
        data.folded = try reader.array()
        data.nameStart = try reader.array()
        data.rawStart = try reader.array()
        data.raw = try reader.array()
        data.altKeys = try reader.array()
        data.altStart = try reader.array()
        data.altOwner = try reader.array()
        try validate(data)
        data.rebuildLookup(capacity: data.count * 2)
        return (header, data)
    }

    /// 长度互相对得上、偏移不越界、父目录编号更小（文件损坏时不至于越界崩溃）
    private static func validate(_ data: IndexData) throws {
        let count = data.count
        guard count > 0, [data.flags.count, data.depths.count, data.sizes.count, data.mtimes.count, data.rawStart.count]
            .allSatisfy({ $0 == count }),
            data.nameStart.count == count + 1, data.nameStart.last.map(Int.init) == data.folded.count,
            data.altStart.count == data.altOwner.count + 1, data.altStart.last.map(Int.init) == data.altKeys.count,
            zip(data.nameStart, data.nameStart.dropFirst()).allSatisfy({ $0 < $1 }),
            data.parents.enumerated().allSatisfy({ $0.offset == 0 || Int($0.element) < $0.offset }),
            data.rawStart.allSatisfy({ $0 == IndexData.sameAsFolded || Int($0) < data.raw.count }),
            data.altOwner.allSatisfy({ Int($0) < count })
        else { throw Failure.badFormat }
    }
}

private struct BinaryWriter {
    var data = Data()

    mutating func bytes(_ bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }

    mutating func value(_ value: some FixedWidthInteger) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func string(_ text: String) {
        array(Array(text.utf8))
    }

    mutating func array(_ values: [some FixedWidthInteger]) {
        value(UInt64(values.count))
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
}

private struct BinaryReader {
    let data: Data
    var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= data.count else { throw IndexPersistence.Failure.badFormat }
        defer { offset += count }
        return Array(data[data.startIndex + offset ..< data.startIndex + offset + count])
    }

    mutating func value<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let raw = try bytes(MemoryLayout<T>.size)
        return T(littleEndian: raw.withUnsafeBytes { $0.loadUnaligned(as: T.self) })
    }

    mutating func string() throws -> String {
        try String(utf8: array() as [UInt8])
    }

    mutating func array<T: FixedWidthInteger>() throws -> [T] {
        let count = try Int(value(UInt64.self))
        let size = count * MemoryLayout<T>.stride
        guard count >= 0, size / MemoryLayout<T>.stride == count, offset + size <= data.count else {
            throw IndexPersistence.Failure.badFormat
        }
        defer { offset += size }
        // 文件里的位置不一定对齐，逐字节拷进新数组（不能直接把那块内存当 T 读）
        let start = offset
        return data.withUnsafeBytes { raw in
            [T](unsafeUninitializedCapacity: count) { buffer, initialized in
                if let destination = buffer.baseAddress, let source = raw.baseAddress, size > 0 {
                    memcpy(destination, source + start, size)
                }
                initialized = count
            }
        }
    }
}
