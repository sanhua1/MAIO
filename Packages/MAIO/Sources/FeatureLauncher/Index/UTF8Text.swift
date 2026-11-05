import Foundation

extension String {
    /// 文件名的字节转字符串（APFS 的文件名总是合法 UTF-8；万一不是，用替换字符显示）
    init(utf8 bytes: some Sequence<UInt8>) {
        let array = Array(bytes)
        self = String(bytes: array, encoding: .utf8) ?? String(repeating: "\u{FFFD}", count: array.isEmpty ? 0 : 1)
    }
}
