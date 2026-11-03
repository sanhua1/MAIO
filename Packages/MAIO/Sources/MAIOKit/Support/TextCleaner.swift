import Foundation

/// 删除多余换行：把从 PDF 等处复制来的断行文字拼回完整段落。
/// 规则：空行（段落分隔）保留；行尾连字符断开的单词拼回；中日韩文字之间直接拼接，其他文字之间加空格。
/// 翻译和截图 OCR 共用（纯文本处理，不涉及服务协议）。
public enum TextCleaner {
    public static func removingLineBreaks(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let paragraphs = splitParagraphs(normalized)
        return paragraphs.map(joinLines).joined(separator: "\n\n")
    }

    private static func splitParagraphs(_ text: String) -> [[String]] {
        var paragraphs: [[String]] = []
        var current: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current)
                    current = []
                }
            } else {
                current.append(trimmed)
            }
        }
        if !current.isEmpty {
            paragraphs.append(current)
        }
        return paragraphs
    }

    private static func joinLines(_ lines: [String]) -> String {
        var result = ""
        for line in lines {
            guard let last = result.last, let first = line.first else {
                result += line
                continue
            }
            if last == "-", result.count >= 2, result.dropLast().last?.isLetter == true, first.isLowercase {
                result.removeLast()
                result += line
            } else if isCJK(last) || isCJK(first) {
                result += line
            } else {
                result += " " + line
            }
        }
        return result
    }

    public static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3000 ... 0x303F, 0x3040 ... 0x30FF, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF,
             0xAC00 ... 0xD7AF, 0xF900 ... 0xFAFF, 0xFF00 ... 0xFFEF:
            return true
        default:
            return false
        }
    }
}
