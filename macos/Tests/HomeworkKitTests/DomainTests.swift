import Foundation
import Testing
@testable import HomeworkKit

// MARK: - 课表调度

@Test func defaultWeeklyIs7x9() {
    let w = Schedule.defaultWeeklySchedule()
    #expect(w.count == 7)
    for row in w { #expect(row.count == PERIODS) }
    #expect(w[0][0] == "语文")
    #expect(w[5].allSatisfy { $0.isEmpty })
    #expect(w[6].allSatisfy { $0.isEmpty })
}

@Test func weekdayHelpers() {
    #expect(Schedule.weekdayIndex("2026-10-01") == 3)
    #expect(Schedule.weekdayCN("2026-10-01") == "星期四")
    #expect(Schedule.addDays("2026-10-01", 1) == "2026-10-02")
    #expect(Schedule.addDays("2026-10-01", -3) == "2026-09-28")
    #expect(Schedule.weekdayShort("2026-10-04") == "周日")
    #expect(Schedule.dotDate("2026-10-01") == "2026.10.1")
    #expect(Schedule.mondayOf("2026-10-01") == "2026-09-28")
}

@Test func effectiveUsesTemplate() {
    let data = AppData()
    let slots = Schedule.effectiveSchedule(data, date: "2026-10-01")
    #expect(slots[0].name == "政治")
    #expect(slots[0].changed == false)
}

@Test func overrideMarksChanged() {
    var data = AppData()
    var day = Day()
    day.scheduleOverride[0] = "数学"
    data.days["2026-10-01"] = day
    let slots = Schedule.effectiveSchedule(data, date: "2026-10-01")
    #expect(slots[0].name == "数学")
    #expect(slots[0].changed)
    #expect(slots[1].changed == false)
}

@Test func overrideSameAsBaseNotChanged() {
    var data = AppData()
    var day = Day()
    day.scheduleOverride[0] = "政治"
    data.days["2026-10-01"] = day
    #expect(Schedule.effectiveSchedule(data, date: "2026-10-01")[0].changed == false)
}

@Test func copiedFromWeekdayOverride() {
    var data = AppData()
    data.days["2026-10-03"] = Day(copiedFromWeekday: 0)
    #expect(Schedule.effectiveSchedule(data, date: "2026-10-03")[0].name == "语文")
}

@Test func suggestionsDedup() {
    let data = AppData()
    let s = Schedule.homeworkSuggestions(Schedule.effectiveSchedule(data, date: "2026-10-01"))
    #expect(s == ["政治", "生物", "数学", "语文", "英语A", "英语B", "物理", "体育"])
}

@Test func suggestionsEnglishSplitOnce() {
    let data = AppData()
    let s = Schedule.homeworkSuggestions(Schedule.effectiveSchedule(data, date: "2026-09-30"))
    #expect(s.filter { $0.hasPrefix("英语") }.count == 2)
    #expect(s.contains("英语A") && s.contains("英语B"))
}

@Test func speechUsesTomorrowSchedule() {
    let data = AppData()
    let today = Schedule.homeworkSuggestions(Schedule.effectiveSchedule(data, date: "2026-10-01"))
    let speech = Schedule.speechSuggestions(data, date: "2026-10-01")
    let friday = Schedule.homeworkSuggestions(Schedule.effectiveSchedule(data, date: "2026-10-02"))
    #expect(speech == friday)
    #expect(speech != today)
}

@Test func prevAndNextSchoolDaySkipWeekend() {
    let data = AppData()
    #expect(Schedule.prevSchoolDay(data, "2026-10-05") == "2026-10-02")
    #expect(Schedule.prevSchoolDay(data, "2026-10-02") == "2026-10-01")
    #expect(Schedule.nextSchoolDay(data, "2026-10-02") == "2026-10-05")
    #expect(Schedule.nextSchoolDay(data, "2026-10-01") == "2026-10-02")
}

@Test func schoolDayRespectsMakeupDay() {
    var data = AppData()
    data.days["2026-10-04"] = Day()
    #expect(Schedule.nextSchoolDay(data, "2026-10-02") == "2026-10-04")
    #expect(Schedule.nextSchoolDay(data, "2026-10-04") == "2026-10-05")
    #expect(Schedule.prevSchoolDay(data, "2026-10-05") == "2026-10-04")
}

@Test func launchViewAroundCutoff() {
    let data = AppData()
    let before = Schedule.launchView(data, today: "2026-10-02", minutes: 7 * 60 + 30)
    #expect(before.submitOnly)
    #expect(before.date == "2026-10-01")
    let after = Schedule.launchView(data, today: "2026-10-02", minutes: 8 * 60)
    #expect(after.submitOnly == false)
    #expect(after.date == "2026-10-02")
    #expect(Schedule.cutoffMinutes("7:5") == 8 * 60)
    #expect(Schedule.cutoffMinutes("07:05") == 7 * 60 + 5)
}

@Test func announcementVisibilityIsGlobal() {
    #expect(Schedule.announcementVisible(Announcement(id: 1, text: "x", done: false)))
    #expect(Schedule.announcementVisible(Announcement(id: 1, text: "x", done: true)) == false)
}

@Test func speechesEmptyCheck() {
    var day = Day()
    #expect(Schedule.speechesEmpty(day))
    day.speeches.append(SpeechEntry(subject: "语文", students: "  "))
    #expect(Schedule.speechesEmpty(day))
    day.speeches.append(SpeechEntry(subject: "数学", students: "24"))
    #expect(Schedule.speechesEmpty(day) == false)
}

@Test func presentHomeworkFilters() {
    var data = AppData()
    data.days["2026-10-01"] = Day(homework: [
        HomeworkItem(subject: "语文", text: "背书", submitNext: true),
        HomeworkItem(subject: "数学", text: "练习册", submitNext: false),
        HomeworkItem(subject: "物理", text: "   ", submitNext: true),
    ])
    #expect(Schedule.presentHomework(data, homeworkDate: "2026-10-01", submitOnly: false).count == 2)
    let sub = Schedule.presentHomework(data, homeworkDate: "2026-10-01", submitOnly: true)
    #expect(sub.count == 1)
    #expect(sub[0].subject == "语文")
    #expect(Schedule.presentHomework(data, homeworkDate: "2026-10-09", submitOnly: false).isEmpty)
}

@Test func viewModelKeepsPageDayWhenSubmitOnly() {
    var data = AppData()
    data.days["2026-10-01"] = Day(
        homework: [HomeworkItem(subject: "语文", text: "背书", submitNext: true)],
        speeches: [SpeechEntry(subject: "数学", students: "24")]
    )
    let all = Schedule.viewModel(data, date: "2026-10-01", submitOnly: false)
    #expect(all.displayDate == "2026-10-01")
    #expect(all.homeworkDate == "2026-10-01")
    #expect(all.weekday == "星期四")
    let submit = Schedule.viewModel(data, date: "2026-10-01", submitOnly: true)
    #expect(submit.date == "2026-10-01")
    #expect(submit.displayDate == "2026-10-02")
    #expect(submit.homework.count == 1)
    #expect(submit.speechWarn == false)
    #expect(submit.homeworkSuggestions == ["政治", "生物", "数学", "语文", "英语A", "英语B", "物理", "体育"])
}

// MARK: - 存储

private func tempDir(_ tag: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("homework_swift_test_\(tag)_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func sample() -> AppData {
    var data = AppData()
    data.days["2026-10-01"] = Day(homework: [HomeworkItem(subject: "语文", text: "背书", submitNext: true)])
    return data
}

@Test func saveAndLoadRoundtrip() throws {
    let dir = tempDir("roundtrip")
    defer { try? FileManager.default.removeItem(at: dir) }
    let data = sample()
    try Store.save(dir, data)
    let loaded = try Store.load(dir)
    #expect(loaded == data)
    let text = try String(contentsOf: Store.dataFile(dir), encoding: .utf8)
    #expect(text.contains("\"submit_next\""))
    #expect(text.contains("\"weekly_schedule\""))
    #expect(text.contains("\"copied_from_weekday\""))
}

@Test func backupCreatedAndPrunedPerDay() throws {
    let dir = tempDir("backup")
    defer { try? FileManager.default.removeItem(at: dir) }
    var data = sample()
    try Store.save(dir, data)
    Thread.sleep(forTimeInterval: 1.1)
    data.announcements.append(Announcement(id: 1, text: "v2"))
    try Store.save(dir, data)
    Thread.sleep(forTimeInterval: 1.1)
    try Store.save(dir, data)
    #expect(Store.listBackups(dir).count == 1, "同一天只保留最新备份")
}

@Test func recoverFromCorruptMain() throws {
    let dir = tempDir("recover")
    defer { try? FileManager.default.removeItem(at: dir) }
    let data = sample()
    try Store.save(dir, data)
    Thread.sleep(forTimeInterval: 1.1)
    try Store.save(dir, data)
    try "{ 损坏".write(to: Store.dataFile(dir), atomically: true, encoding: .utf8)
    let (recovered, notice) = Store.loadOrRecover(dir)
    #expect(recovered == data)
    #expect(notice != nil)
    #expect((try? Store.load(dir)) != nil, "恢复后应回写主文件")
}

@Test func ignoresLegacyFieldsOnLoad() throws {
    let json = """
    {
      "version": 1, "weekly_schedule": [], "days": {},
      "announcements": [{"id": 1, "text": "旧公告", "created_date": "2026-09-30", "done": true, "done_date": "2026-10-01"}],
      "settings": {"data_dir": null, "image_interval_secs": 60, "morning_cutoff": "08:00", "show_badge": true, "last_seen_date": "2026-10-01"}
    }
    """
    let data = try Store.makeDecoder().decode(AppData.self, from: Data(json.utf8))
    #expect(data.announcements.count == 1)
    #expect(data.announcements[0].done)
    #expect(data.announcements[0].text == "旧公告")
    #expect(data.weeklySchedule.count == 7)
}

@Test func emptyDirGivesDefaultWithNotice() {
    let dir = tempDir("empty")
    defer { try? FileManager.default.removeItem(at: dir) }
    let (data, notice) = Store.loadOrRecover(dir)
    #expect(data.days.isEmpty)
    #expect(notice != nil)
}

@Test func migrateCopiesAndVerifies() throws {
    let src = tempDir("migrate_src")
    let dst = tempDir("migrate_dst")
    defer {
        try? FileManager.default.removeItem(at: src)
        try? FileManager.default.removeItem(at: dst)
    }
    Store.configRootOverride = tempDir("config")
    defer { Store.configRootOverride = nil }
    try Store.save(src, sample())
    try Store.migrate(from: src, to: dst)
    #expect(try Store.load(dst) == sample())
    #expect(FileManager.default.fileExists(atPath: Store.dataFile(src).path), "旧目录保留")
}

@Test func migrateRejectsSameDir() throws {
    let src = tempDir("migrate_same")
    defer { try? FileManager.default.removeItem(at: src) }
    try Store.save(src, sample())
    #expect(throws: StoreError.self) { try Store.migrate(from: src, to: src) }
}

@Test func exportImageCleansOtherDays() throws {
    let dir = tempDir("export")
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try Store.exportImage(Data([1, 2, 3]), dir: dir, date: "2026-09-30")
    let path = try Store.exportImage(Data([4, 5, 6]), dir: dir, date: "2026-10-01")
    #expect(path.lastPathComponent == "家庭作业_2026-10-01.png")
    let items = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(items.filter { $0.hasPrefix(Store.imagePrefix) }.count == 1)
}

// MARK: - 节假日 / 调休

/// 本机「中国大陆节假日」日历里 2026 年国庆的真实数据
private func nationalDayTable() -> HolidayTable {
    var entries: [String: HolidayEntry] = [:]
    for offset in 0..<7 {
        let date = Schedule.addDays("2026-10-01", offset)
        entries[date] = HolidayEntry(date: date, name: "国庆节", isHoliday: true, isWorkday: false)
    }
    for date in ["2026-09-20", "2026-10-10"] {
        entries[date] = HolidayEntry(date: date, name: "国庆节", isHoliday: false, isWorkday: true)
    }
    for offset in 0..<3 {
        let date = Schedule.addDays("2026-09-25", offset)
        entries[date] = HolidayEntry(date: date, name: "中秋节", isHoliday: true, isWorkday: false)
    }
    entries["2026-10-08"] = HolidayEntry(date: "2026-10-08", name: "寒露", isHoliday: false, isWorkday: false)
    return HolidayTable(entries: entries, updatedAt: Date(), calendarTitle: "中国大陆节假日")
}

@Test func holidayTitleParsing() {
    let rest = HolidayRules.parse(title: "国庆节（休）")
    #expect(rest?.name == "国庆节")
    #expect(rest?.isHoliday == true)
    #expect(rest?.isWorkday == false)

    let work = HolidayRules.parse(title: "国庆节（班）")
    #expect(work?.name == "国庆节")
    #expect(work?.isWorkday == true)

    let plain = HolidayRules.parse(title: "元旦")
    #expect(plain?.isHoliday == true)

    #expect(HolidayRules.parse(title: "寒露") == nil, "节气不是节假日")
    #expect(HolidayRules.parse(title: "tyc预定的会议") == nil)
    #expect(HolidayRules.parse(title: "调休上班 国庆节")?.isWorkday == true)
}

@Test func holidayGreetings() {
    #expect(HolidayRules.greeting(for: "国庆节") == "国庆快乐")
    #expect(HolidayRules.greeting(for: "中秋节") == "中秋快乐")
    #expect(HolidayRules.greeting(for: "元旦") == "元旦快乐")
    #expect(HolidayRules.greeting(for: "春节") == "春节快乐")
    #expect(HolidayRules.greeting(for: "清明节") == "清明安康")
}

@Test func dayKindClassification() {
    let table = nationalDayTable()
    let data = AppData()
    let userDays = Set(data.days.keys)
    #expect(HolidayRules.classify("2026-10-01", table: table, userDays: userDays) == .holiday(name: "国庆节"))
    #expect(HolidayRules.classify("2026-10-03", table: table, userDays: userDays) == .holiday(name: "国庆节"), "假期中的周六仍算假期")
    #expect(HolidayRules.classify("2026-10-10", table: table, userDays: userDays) == .makeup(name: "国庆节"))
    #expect(HolidayRules.classify("2026-10-08", table: table, userDays: userDays) == .school, "节气不影响上学")
    #expect(HolidayRules.classify("2026-10-17", table: table, userDays: userDays) == .weekend)
    #expect(HolidayRules.classify("2026-10-08", table: nil, userDays: userDays) == .school)
}

@Test func schoolDaySkipsWholeHoliday() {
    let table = nationalDayTable()
    let data = AppData()
    // 10/8 早上打开时，上一上学日应跳过整个假期回到 9/30
    #expect(Schedule.prevSchoolDay(data, "2026-10-08", holidays: table) == "2026-09-30")
    // 9/30 的下一上学日直接跳到 10/8（10/1-10/7 全放假）
    #expect(Schedule.nextSchoolDay(data, "2026-09-30", holidays: table) == "2026-10-08")
    // 10/10（周六）是调休上课日 → 算上学日
    #expect(Schedule.isSchoolDay(data, "2026-10-10", holidays: table))
    #expect(Schedule.nextSchoolDay(data, "2026-10-08", holidays: table) == "2026-10-09")
    // 假期结束后的周五下午，下一上学日是调休的周六
    #expect(Schedule.nextSchoolDay(data, "2026-10-09", holidays: table) == "2026-10-10")
}

@Test func viewModelCarriesDayKindAndBlanksHolidaySchedule() {
    let table = nationalDayTable()
    let data = AppData()
    let holiday = Schedule.viewModel(data, date: "2026-10-01", submitOnly: false, holidays: table)
    #expect(holiday.dayKind == .holiday(name: "国庆节"))
    #expect(holiday.dayKind.isRestDay)
    #expect(holiday.dayKind.greeting == "国庆快乐")
    #expect(holiday.slots.allSatisfy { $0.name.isEmpty }, "法定节假日不显示课表")

    let weekend = Schedule.viewModel(data, date: "2026-10-17", submitOnly: false, holidays: table)
    #expect(weekend.dayKind == .weekend)
    #expect(weekend.dayKind.greeting == "周末休息")

    let makeup = Schedule.viewModel(data, date: "2026-10-10", submitOnly: false, holidays: table)
    #expect(makeup.dayKind.makeupName == "国庆节")

    // 用户自己给周末建了条目 → 视为调休上学日
    var withUserDay = data
    withUserDay.days["2026-10-17"] = Day()
    #expect(HolidayRules.classify("2026-10-17", table: table, userDays: Set(withUserDay.days.keys)) == .makeup(name: "调休"))
}

@Test func pendingMakeupReminder() {
    let table = nationalDayTable()
    let data = AppData()
    let pending = HolidayRules.pendingMakeupDays(
        table: table, userDays: Set(data.days.keys), from: "2026-10-01", within: 21
    )
    #expect(pending == ["2026-10-10"])
    var withDay = data
    withDay.days["2026-10-10"] = Day()
    #expect(HolidayRules.pendingMakeupDays(
        table: table, userDays: Set(withDay.days.keys), from: "2026-10-01", within: 21
    ).isEmpty)
}
