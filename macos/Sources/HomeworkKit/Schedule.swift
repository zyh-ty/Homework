import Foundation

public enum DateFmt {
    public static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    public static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.timeZone = .current
        return f
    }()

    public static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        f.timeZone = .current
        return f
    }()
}

public enum Schedule {
    public static func defaultWeeklySchedule() -> [[String]] {
        let rows: [[String]] = [
            ["语文", "数学", "历史", "物理", "地理", "体育", "美术", "英语", "班会"],
            ["数学", "物理", "英语", "英语", "语文", "自习", "信息", "政治", "体育"],
            ["数学", "语文", "劳技", "英语", "英语", "心理", "数学", "历史", "生物"],
            ["政治", "生物", "数学", "语文", "语文", "英语", "英语", "物理", "体育"],
            ["语文", "英语", "英语", "数学", "体育", "信息", "物理", "地理", "音乐"],
            [],
            [],
        ]
        return normalizeWeekly(rows)
    }

    public static func normalizeWeekly(_ rows: [[String]]) -> [[String]] {
        var out = rows
        while out.count < 7 { out.append([]) }
        if out.count > 7 { out = Array(out.prefix(7)) }
        for i in out.indices {
            var row = out[i]
            while row.count < PERIODS { row.append("") }
            if row.count > PERIODS { row = Array(row.prefix(PERIODS)) }
            out[i] = row
        }
        return out
    }

    public static func normalizedOverride(_ value: [String?]?) -> [String?] {
        var out = value ?? []
        while out.count < PERIODS { out.append(nil) }
        if out.count > PERIODS { out = Array(out.prefix(PERIODS)) }
        return out
    }

    public static func todayString(_ now: Date = Date()) -> String {
        DateFmt.ymd.string(from: now)
    }

    public static func parse(_ s: String) -> Date? {
        DateFmt.ymd.date(from: s)
    }

    public static func format(_ d: Date) -> String {
        DateFmt.ymd.string(from: d)
    }

    public static func addDays(_ s: String, _ days: Int) -> String {
        guard let d = parse(s) else { return s }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        guard let nd = cal.date(byAdding: .day, value: days, to: d) else { return s }
        return format(nd)
    }

    /// 0 = 周一 … 6 = 周日
    public static func weekdayIndex(_ s: String) -> Int? {
        guard let d = parse(s) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let wd = cal.component(.weekday, from: d) // 1 = 周日
        return (wd + 5) % 7
    }

    public static func weekdayCN(_ s: String) -> String {
        let names = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
        guard let i = weekdayIndex(s) else { return "" }
        return names[i]
    }

    public static func weekdayShort(_ s: String) -> String {
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        guard let i = weekdayIndex(s) else { return "" }
        return names[i]
    }

    public static func mondayOf(_ s: String) -> String {
        let idx = weekdayIndex(s) ?? 0
        return addDays(s, -idx)
    }

    /// 点分日期：2026.10.1
    public static func dotDate(_ s: String) -> String {
        let parts = s.split(separator: "-")
        guard parts.count == 3 else { return s }
        let m = Int(parts[1]) ?? 0
        let d = Int(parts[2]) ?? 0
        return "\(parts[0]).\(m).\(d)"
    }

    /// 合成某天实际课表：调休来源或周模版 + 当日 override（override 与模版不同则标 changed）
    public static func effectiveSchedule(_ data: AppData, date: String) -> [Slot] {
        let day = data.days[date]
        let baseIdx = day?.copiedFromWeekday ?? weekdayIndex(date) ?? 0
        let base = (baseIdx >= 0 && baseIdx < data.weeklySchedule.count) ? data.weeklySchedule[baseIdx] : []
        var slots: [Slot] = []
        slots.reserveCapacity(PERIODS)
        for i in 0..<PERIODS {
            let baseName = i < base.count ? base[i] : ""
            let override = day.flatMap { $0.scheduleOverride.indices.contains(i) ? $0.scheduleOverride[i] : nil } ?? nil
            if let v = override, v != baseName {
                slots.append(Slot(name: v, changed: true))
            } else {
                slots.append(Slot(name: baseName, changed: false))
            }
        }
        return slots
    }

    /// 作业建议学科：课表去重，英语拆成 英语A/英语B
    public static func homeworkSuggestions(_ slots: [Slot]) -> [String] {
        var out: [String] = []
        for s in slots where !s.name.isEmpty {
            if s.name == "英语" {
                for e in ["英语A", "英语B"] where !out.contains(e) {
                    out.append(e)
                }
            } else if !out.contains(s.name) {
                out.append(s.name)
            }
        }
        return out
    }

    /// 演讲建议学科：下一个上学日
    public static func speechSuggestions(_ data: AppData, date: String, holidays: HolidayTable? = nil) -> [String] {
        homeworkSuggestions(effectiveSchedule(data, date: nextSchoolDay(data, date, holidays: holidays)))
    }

    public static func prevSchoolDay(_ data: AppData, _ today: String, holidays: HolidayTable? = nil) -> String {
        stepSchoolDay(data, today, -1, holidays: holidays)
    }

    public static func nextSchoolDay(_ data: AppData, _ date: String, holidays: HolidayTable? = nil) -> String {
        stepSchoolDay(data, date, 1, holidays: holidays)
    }

    /// 上学日判定：**老师建过这一天 → 一定算上学日**（用户数据优先）；
    /// 否则日历判为放假 → 不算；再否则工作日（周一至周五）算。
    /// 日历只能「扣掉」假期，不能凭空添加课：调休上课日要老师自己建天
    /// （编辑页横幅提醒 + 一键加入），加入后自然生效。
    public static func isSchoolDay(_ data: AppData, _ date: String, holidays: HolidayTable? = nil) -> Bool {
        if data.days[date] != nil { return true }
        if holidays?.entry(on: date)?.isHoliday == true { return false }
        return (weekdayIndex(date) ?? 0) < 5
    }

    /// 调休日的默认课表来源：往前找最近的一个上学日，按它的星期几上课。
    /// 原来传 nil 会让调休日取当天（周六/周日）的空模版，得到一张空课表。
    public static func defaultCopyFrom(_ data: AppData, date: String, holidays: HolidayTable? = nil) -> Int? {
        let previous = prevSchoolDay(data, date, holidays: holidays)
        guard previous != date else { return nil }
        return weekdayIndex(previous)
    }

    private static func stepSchoolDay(_ data: AppData, _ from: String, _ step: Int, holidays: HolidayTable?) -> String {
        var current = from
        for _ in 0..<30 {
            current = addDays(current, step)
            if isSchoolDay(data, current, holidays: holidays) {
                return current
            }
        }
        return current
    }

    /// "08:00" → 分钟数，非法值回退 8:00
    public static func cutoffMinutes(_ s: String) -> Int {
        let parts = s.split(separator: ":")
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else {
            return 8 * 60
        }
        return h * 60 + m
    }

    public static func minutesOfDay(_ date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// 启动/重定位：早于 cutoff → 上一上学日 + 仅要交；否则今天 + 全部
    public static func launchView(_ data: AppData, today: String, minutes: Int, holidays: HolidayTable? = nil) -> LaunchView {
        if minutes < cutoffMinutes(data.settings.morningCutoff) {
            return LaunchView(date: prevSchoolDay(data, today, holidays: holidays), submitOnly: true)
        }
        return LaunchView(date: today, submitOnly: false)
    }

    public static func announcementVisible(_ a: Announcement) -> Bool {
        !a.done
    }

    public static func speechesEmpty(_ day: Day?) -> Bool {
        guard let day else { return true }
        return day.speeches.allSatisfy { $0.students.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public static func presentHomework(_ data: AppData, homeworkDate: String, submitOnly: Bool) -> [HomeworkItem] {
        guard let day = data.days[homeworkDate] else { return [] }
        return day.homework.filter { item in
            !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (!submitOnly || item.submitNext)
        }
    }

    /// 前端渲染所需的一切（对齐原 get_view_model 命令）
    public static func viewModel(
        _ data: AppData,
        date: String,
        submitOnly: Bool,
        holidays: HolidayTable? = nil
    ) -> ViewModel {
        let displayDate = submitOnly ? nextSchoolDay(data, date, holidays: holidays) : date
        let day = data.days[date]
        let displaySlots = effectiveSchedule(data, date: displayDate)
        let pageSlots = effectiveSchedule(data, date: date)
        let kind = HolidayRules.classify(displayDate, table: holidays, userDays: Set(data.days.keys))
        return ViewModel(
            date: date,
            displayDate: displayDate,
            weekday: weekdayCN(displayDate),
            submitOnly: submitOnly,
            homeworkDate: date,
            slots: displaySlots,
            announcements: data.announcements.filter(announcementVisible),
            homework: presentHomework(data, homeworkDate: date, submitOnly: submitOnly),
            speeches: day?.speeches ?? [],
            speechWarn: speechesEmpty(day),
            homeworkSuggestions: homeworkSuggestions(pageSlots),
            speechSuggestions: speechSuggestions(data, date: date, holidays: holidays),
            dayKind: kind
        )
    }

    public static func weekOverview(_ data: AppData, monday: String) -> WeekOverview {
        var dates: [String] = []
        var rows: [[Slot]] = []
        for i in 0..<7 {
            let d = addDays(monday, i)
            dates.append(d)
            rows.append(effectiveSchedule(data, date: d))
        }
        return WeekOverview(dates: dates, rows: rows)
    }
}
