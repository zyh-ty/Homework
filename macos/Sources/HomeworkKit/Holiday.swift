import Foundation

/// 日历里的一条节假日/调休记录
public struct HolidayEntry: Codable, Hashable, Sendable {
    public var date: String
    /// 节日基础名，如「国庆节」「中秋节」「元旦」
    public var name: String
    /// 放假
    public var isHoliday: Bool
    /// 调休上班（补课）
    public var isWorkday: Bool

    public init(date: String, name: String, isHoliday: Bool, isWorkday: Bool) {
        self.date = date
        self.name = name
        self.isHoliday = isHoliday
        self.isWorkday = isWorkday
    }
}

/// 节假日表：来自系统日历「中国大陆节假日」，可缓存到磁盘
public struct HolidayTable: Codable, Hashable, Sendable {
    public var entries: [String: HolidayEntry]
    public var updatedAt: Date
    public var calendarTitle: String?

    public init(entries: [String: HolidayEntry] = [:], updatedAt: Date = Date(), calendarTitle: String? = nil) {
        self.entries = entries
        self.updatedAt = updatedAt
        self.calendarTitle = calendarTitle
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func entry(on date: String) -> HolidayEntry? { entries[date] }

    /// 放假日返回节日名
    public func holidayName(on date: String) -> String? {
        guard let entry = entries[date], entry.isHoliday, !entry.isWorkday else { return nil }
        return entry.name
    }

    /// 调休上课日（日历标注的「（班）」）
    public func isMakeupWorkday(_ date: String) -> Bool {
        entries[date]?.isWorkday ?? false
    }

    public var holidayDates: [String] {
        entries.values.filter { $0.isHoliday && !$0.isWorkday }.map(\.date).sorted()
    }

    public var workdayDates: [String] {
        entries.values.filter(\.isWorkday).map(\.date).sorted()
    }
}

/// 某一天的性质
public enum DayKind: Hashable, Sendable {
    case school
    case weekend
    case holiday(name: String)
    case makeup(name: String)

    /// 不用上课（作业可以跳过）
    public var isRestDay: Bool {
        switch self {
        case .holiday, .weekend: return true
        case .school, .makeup: return false
        }
    }

    public var holidayName: String? {
        if case .holiday(let name) = self { return name }
        return nil
    }

    public var makeupName: String? {
        if case .makeup(let name) = self { return name }
        return nil
    }

    /// 放映/编辑页上的大字问候语
    public var greeting: String? {
        switch self {
        case .holiday(let name): return HolidayRules.greeting(for: name)
        case .weekend: return "周末休息"
        case .school, .makeup: return nil
        }
    }

    /// 副标题
    public var subtitle: String? {
        switch self {
        case .holiday(let name): return "\(name)假期 · 今天没有作业"
        case .weekend: return "今天没有课，好好放松"
        case .makeup(let name): return "\(name) · 调休上课日"
        case .school: return nil
        }
    }

    public var symbol: String {
        switch self {
        case .holiday: return "party.popper.fill"
        case .weekend: return "cup.and.saucer.fill"
        case .makeup: return "arrow.triangle.2.circlepath"
        case .school: return "graduationcap.fill"
        }
    }
}

public enum HolidayRules {
    /// 法定节假日（只认这些，节气/纪念日不算）
    public static let statutory: Set<String> = [
        "元旦", "春节", "除夕", "清明节", "劳动节", "端午节", "中秋节", "国庆节", "国庆",
    ]

    /// 「国庆节（休）」→（国庆节, 放假）；「国庆节（班）」→（国庆节, 调休上班）
    public static func parse(title: String) -> (name: String, isHoliday: Bool, isWorkday: Bool)? {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var workday = false
        var holiday = false

        for token in ["调休上班", "调休补班", "调休", "补班", "上班"] where text.hasPrefix(token) {
            workday = true
            text = String(text.dropFirst(token.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        for token in ["（休）", "(休)", "放假", "休息"] where text.contains(token) {
            holiday = true
            text = text.replacingOccurrences(of: token, with: "")
        }
        for token in ["（班）", "(班)", "（调休）", "(调休)", "补班", "上班"] where text.contains(token) {
            workday = true
            text = text.replacingOccurrences(of: token, with: "")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let candidates = statutory.sorted { $0.count > $1.count }
        guard let name = candidates.first(where: { text.contains($0) }) else { return nil }
        if workday { holiday = false }
        if !workday && !holiday { holiday = true }
        return (name, holiday, workday)
    }

    /// 节日的问候语：国庆节 → 国庆快乐，中秋节 → 中秋快乐
    public static func greeting(for name: String) -> String {
        switch name {
        case "国庆节", "国庆": return "国庆快乐"
        case "中秋节", "中秋": return "中秋快乐"
        case "元旦": return "元旦快乐"
        case "春节", "除夕": return "春节快乐"
        case "清明节", "清明": return "清明安康"
        case "劳动节", "劳动": return "劳动节快乐"
        case "端午节", "端午": return "端午安康"
        default: return name.replacingOccurrences(of: "节", with: "") + "快乐"
        }
    }

    /// 用日历（+ 用户自己添加的调休日）判断某天性质
    public static func classify(_ date: String, table: HolidayTable?, userDays: Set<String> = []) -> DayKind {
        if let entry = table?.entry(on: date) {
            if entry.isWorkday { return .makeup(name: entry.name) }
            if entry.isHoliday { return .holiday(name: entry.name) }
        }
        let weekday = Schedule.weekdayIndex(date) ?? 0
        if weekday >= 5 {
            // 用户手动加了这一天的条目的周末 = 自己安排的调休上学日
            return userDays.contains(date) ? .makeup(name: "调休") : .weekend
        }
        return .school
    }

    /// 未来若干天里「日历说是调休上课、但还没在软件里建过」的日期
    public static func pendingMakeupDays(
        table: HolidayTable?,
        userDays: Set<String>,
        from date: String,
        within days: Int = 21
    ) -> [String] {
        guard let table else { return [] }
        var out: [String] = []
        for offset in 0...max(0, days) {
            let candidate = Schedule.addDays(date, offset)
            guard table.isMakeupWorkday(candidate) else { continue }
            if userDays.contains(candidate) { continue }
            out.append(candidate)
        }
        return out
    }
}
