import Foundation

/// `dm:`：修改时间。
/// - 关键词：today、yesterday、thisweek、lastweek、thismonth、lastmonth、thisyear、lastyear、pastweek、pastmonth、pastyear；
/// - 最近 N 天 / 周 / 月 / 年：`7d`、`2w`、`3m`、`1y`；
/// - 日期：`2024-05-01`（也可以用 / 或 .）、`2024-05`、`2024`；
/// - 比较和区间：`>=2024-01-01`、`2024-01-01..2024-03-31`。
enum DateFilter {
    /// 一段时间：[start, end)，秒
    struct Period {
        var start: Date
        var end: Date
    }

    static func parse(_ value: String, context: QueryContext) -> FileExpr {
        let text = value.lowercased().trimmingCharacters(in: .whitespaces)
        if let dots = text.range(of: "..") {
            guard let from = period(text[..<dots.lowerBound], context), let to = period(text[dots.upperBound...], context),
                  from.start < to.end
            else { return .term(.nothing) }
            return .term(.modified(seconds(from.start) ... seconds(to.end) - 1))
        }
        let comparison = Comparison<Period>.parse(text) { period($0, context) }
        return comparison?.expression(
            lowest: UInt32.min, highest: UInt32.max, start: { seconds($0.start) }, end: { seconds($0.end) - 1 },
            make: FileTerm.modified,
        ) ?? .term(.nothing)
    }

    private static func seconds(_ date: Date) -> UInt32 {
        UInt32(clamping: Int(date.timeIntervalSince1970.rounded(.down)))
    }

    static func period(_ text: Substring, _ context: QueryContext) -> Period? {
        let text = String(text)
        return keyword(text, context) ?? recent(text, context) ?? absolute(text, context)
    }

    private static func keyword(_ text: String, _ context: QueryContext) -> Period? {
        let calendar = context.calendar
        let now = context.now
        func current(_ unit: Calendar.Component, offset: Int = 0) -> Period? {
            guard let interval = calendar.dateInterval(of: unit, for: now),
                  let start = calendar.date(byAdding: unit, value: offset, to: interval.start),
                  let end = calendar.date(byAdding: unit, value: offset, to: interval.end)
            else { return nil }
            return Period(start: start, end: end)
        }
        func past(_ unit: Calendar.Component) -> Period? {
            calendar.date(byAdding: unit, value: -1, to: now).map { Period(start: $0, end: now.addingTimeInterval(1)) }
        }
        switch text {
        case "today": return current(.day)
        case "yesterday": return current(.day, offset: -1)
        case "thisweek": return current(.weekOfYear)
        case "lastweek": return current(.weekOfYear, offset: -1)
        case "thismonth": return current(.month)
        case "lastmonth": return current(.month, offset: -1)
        case "thisyear": return current(.year)
        case "lastyear": return current(.year, offset: -1)
        case "pastweek": return past(.weekOfYear)
        case "pastmonth": return past(.month)
        case "pastyear": return past(.year)
        default: return nil
        }
    }

    /// `7d` = 最近 7 天（从现在往前推）
    private static func recent(_ text: String, _ context: QueryContext) -> Period? {
        let units: [Character: Calendar.Component] = ["d": .day, "w": .weekOfYear, "m": .month, "y": .year]
        guard let last = text.last, let unit = units[last], let count = Int(text.dropLast()), count > 0,
              let start = context.calendar.date(byAdding: unit, value: -count, to: context.now)
        else { return nil }
        return Period(start: start, end: context.now.addingTimeInterval(1))
    }

    /// `2024-05-01`、`2024/05`、`2024`
    private static func absolute(_ text: String, _ context: QueryContext) -> Period? {
        let parts = text.split { $0 == "-" || $0 == "/" || $0 == "." }.compactMap { Int($0) }
        guard (1 ... 3).contains(parts.count), parts.count == text.split(whereSeparator: { "-/.".contains($0) }).count,
              parts[0] >= 1970
        else { return nil }
        let unit: Calendar.Component = [.year, .month, .day][parts.count - 1]
        var components = DateComponents(
            year: parts[0],
            month: parts.count > 1 ? parts[1] : 1,
            day: parts.count > 2 ? parts[2] : 1,
        )
        components.calendar = context.calendar
        guard let start = context.calendar.date(from: components), let end = context.calendar.date(
            byAdding: unit,
            value: 1,
            to: start,
        )
        else { return nil }
        return Period(start: start, end: end)
    }
}

extension DateFilter.Period: Comparable {
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.start < rhs.start
    }
}
