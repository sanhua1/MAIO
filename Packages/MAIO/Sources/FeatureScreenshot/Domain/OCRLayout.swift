import CoreGraphics
import Foundation

/// OCR 识别出的一行文字
struct RecognizedLine: Equatable {
    var text: String
    /// 在图片里的位置：归一化坐标（0...1），左上角原点
    var box: CGRect
}

/// 把 Vision 逐行返回的结果拼成文字（spec 4.5）：
/// 按从上到下分行，同一行里（例如左右两栏、表格）从左到右用空格连接；
/// 行间距明显大于行高时认为是新段落，中间空一行（"删除换行"按空行保留段落）。
enum OCRLayout {
    /// 行间距超过行高的这个倍数时算新段落
    static let paragraphGap: CGFloat = 0.9

    static func text(from lines: [RecognizedLine]) -> String {
        let rows = rows(from: lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
        var result = ""
        var previous: CGRect?
        for row in rows {
            let frame = row.map(\.box).reduce(CGRect.null) { $0.union($1) }
            if let previous {
                let height = min(previous.height, frame.height)
                result += frame.minY - previous.maxY > height * paragraphGap ? "\n\n" : "\n"
            }
            result += row.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            previous = frame
        }
        return result
    }

    /// 分行：垂直方向的中心落在当前行范围内的，归到同一行
    static func rows(from lines: [RecognizedLine]) -> [[RecognizedLine]] {
        var rows: [[RecognizedLine]] = []
        for line in lines.sorted(by: { $0.box.minY < $1.box.minY }) {
            if let last = rows.last, let band = last.map(\.box).reduce(nil, { ($0 ?? $1).union($1) }),
               band.minY ... band.maxY ~= line.box.midY {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX } }
    }
}
