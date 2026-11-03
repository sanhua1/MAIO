import Foundation

/// 一条截图历史（ADR-0012）。图片文件放在 `<历史目录>/<id>/`。
struct ScreenshotRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var createdAt: Date
    var pixelWidth: Int
    var pixelHeight: Int
    /// 截图时最前面的 App
    var sourceApp: String?
    /// OCR 识别出的文字（P4），用于搜索
    var ocrText: String?
    /// 这条记录占用的字节数（全部文件）
    var bytes: Int64
    var pinned = false
    /// 有标注时才有 annotations.json 和 rendered.png；没有标注时最终图就是 original.png
    var hasAnnotations = false
    /// 截图时每 pt 的像素数（重新编辑标注时用，annotations.json 的坐标单位是 pt）
    var scale: Double?
}

/// `index.json` 的内容。
struct ScreenshotIndex: Codable, Equatable, Sendable {
    var version = 1
    /// 按时间倒序（最新的在前）
    var records: [ScreenshotRecord] = []
}

/// 保存截图时的文件名：`MAIO 2026-11-03 14.05.33.png`，重名时加序号。
enum ScreenshotFileName {
    static func make(date: Date, timeZone: TimeZone = .current, existing: (String) -> Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?) -> String {
            let text = String(value ?? 0)
            return text.count < 2 ? "0" + text : text
        }
        let base = "MAIO \(parts.year ?? 0)-\(pad(parts.month))-\(pad(parts.day)) "
            + "\(pad(parts.hour)).\(pad(parts.minute)).\(pad(parts.second))"
        var name = base + ".png"
        var index = 2
        while existing(name) {
            name = "\(base) \(index).png"
            index += 1
        }
        return name
    }
}
