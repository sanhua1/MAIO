import Darwin

// 参考：references/oil-find/Sources/COilFind/coilfind.c（sift_read_dir，MIT，Copyright (c) 2026 Lin Zhihuang）
/// 用 `getattrlistbulk` 读一个目录：一次系统调用拿到一批子项的名称、类型、大小、修改时间、标志，不用逐个 stat。
struct DirectoryReader {
    struct Entry {
        /// 指向读缓冲区里的名称（UTF-8，不含结尾的 0），下一次 `read` 后失效
        var name: UnsafeBufferPointer<UInt8>
        var device: Int32
        var type: UInt32
        var modified: Int
        var bsdFlags: UInt32
        var size: UInt64
        var error: Int32
    }

    static let bufferSize = 256 * 1024

    private let buffer: UnsafeMutableRawPointer
    private var attributes = attrlist()

    init() {
        buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.bufferSize, alignment: 8)
        attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_ERROR) | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_FLAGS)
        attributes.fileattr = attrgroup_t(ATTR_FILE_DATALENGTH)
    }

    func deallocate() {
        buffer.deallocate()
    }

    /// 读下一批。返回 false 表示读完或出错（`errno` 说明原因）
    mutating func read(_ descriptor: Int32, into entries: inout [Entry]) -> Bool {
        entries.removeAll(keepingCapacity: true)
        var count: Int32
        repeat {
            count = getattrlistbulk(descriptor, &attributes, buffer, Self.bufferSize, 0)
        } while count < 0 && errno == EINTR
        guard count > 0 else {
            return false
        }
        var cursor = UnsafeRawPointer(buffer)
        let limit = cursor + Self.bufferSize
        for _ in 0 ..< count {
            let length = Int(cursor.loadUnaligned(as: UInt32.self))
            guard length >= 8, cursor + length <= limit else { return false }
            if let entry = Self.parse(cursor, end: cursor + length) {
                entries.append(entry)
            }
            cursor += length
        }
        return true
    }

    /// 一条记录：长度、返回了哪些属性，然后按属性位从小到大排列（ERROR 例外，紧跟在后面），每项按 4 字节对齐
    private static func parse(_ start: UnsafeRawPointer, end: UnsafeRawPointer) -> Entry? {
        var cursor = start + 4
        let returned = cursor.loadUnaligned(as: attribute_set_t.self)
        cursor += MemoryLayout<attribute_set_t>.size
        var entry = Entry(
            name: UnsafeBufferPointer(start: nil, count: 0),
            device: 0,
            type: 0,
            modified: 0,
            bsdFlags: 0,
            size: 0,
            error: 0,
        )
        func take<T>(_: T.Type) -> T {
            let value = cursor.loadUnaligned(as: T.self)
            cursor += (MemoryLayout<T>.size + 3) & ~3
            return value
        }
        let common = returned.commonattr
        if common & attrgroup_t(ATTR_CMN_ERROR) != 0 {
            entry.error = take(Int32.self)
        }
        if common & attrgroup_t(ATTR_CMN_NAME) != 0 {
            let reference = cursor.loadUnaligned(as: attrreference_t.self)
            let text = cursor + Int(reference.attr_dataoffset)
            _ = take(attrreference_t.self)
            guard text >= start, text < end else { return nil }
            let bytes = text.assumingMemoryBound(to: UInt8.self)
            entry.name = UnsafeBufferPointer(start: bytes, count: strnlen(text.assumingMemoryBound(to: CChar.self), end - text))
        }
        if common & attrgroup_t(ATTR_CMN_DEVID) != 0 {
            entry.device = take(Int32.self)
        }
        if common & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
            entry.type = take(UInt32.self)
        }
        if common & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
            entry.modified = take(timespec.self).tv_sec
        }
        if common & attrgroup_t(ATTR_CMN_FLAGS) != 0 {
            entry.bsdFlags = take(UInt32.self)
        }
        if returned.fileattr & attrgroup_t(ATTR_FILE_DATALENGTH) != 0 {
            entry.size = UInt64(max(0, take(off_t.self)))
        }
        return entry
    }
}
