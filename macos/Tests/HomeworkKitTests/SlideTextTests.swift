import Foundation
import Testing
@testable import HomeworkKit

private func viewModel(
    homework: [HomeworkItem] = [],
    speeches: [SpeechEntry] = [],
    announcements: [Announcement] = [],
    submitOnly: Bool = false,
    dayKind: DayKind = .school
) -> ViewModel {
    ViewModel(
        date: "2026-10-01",
        displayDate: submitOnly ? "2026-10-02" : "2026-10-01",
        weekday: "星期四",
        submitOnly: submitOnly,
        homeworkDate: "2026-10-01",
        slots: Schedule.effectiveSchedule(AppData(), date: "2026-10-01"),
        announcements: announcements,
        homework: homework,
        speeches: speeches,
        speechWarn: speeches.isEmpty,
        homeworkSuggestions: [],
        speechSuggestions: [],
        dayKind: dayKind
    )
}

@Test func textSingleItemHasNoOrdinal() {
    let vm = viewModel(homework: [HomeworkItem(subject: "语文", text: "抄写第 3 课生字")])
    let text = SlideText.plain(vm)
    #expect(text.contains("语文：抄写第 3 课生字"))
    #expect(!text.contains("1."))
}

@Test func textMultipleItemsNumberedAndTagged() {
    let vm = viewModel(homework: [
        HomeworkItem(subject: "数学", text: "练习册 P12"),
        HomeworkItem(subject: "数学", text: "口算题卡", submitNext: true),
    ])
    let text = SlideText.plain(vm)
    #expect(text.contains("数学：\n　1. 练习册 P12\n　2. 口算题卡（明天交）"))
}

@Test func textKeepsSubjectOrderAndSplitsEnglish() {
    let vm = viewModel(homework: [
        HomeworkItem(subject: "英语A", text: "背单词 P20"),
        HomeworkItem(subject: "语文", text: "背诵古诗"),
        HomeworkItem(subject: "英语B", text: "八篇阅读"),
    ])
    let text = SlideText.plain(vm)
    let order = ["英语A：背单词 P20", "语文：背诵古诗", "英语B：八篇阅读"]
    let positions = order.compactMap { text.range(of: $0)?.lowerBound }
    #expect(positions.count == 3)
    #expect(positions == positions.sorted())
}

@Test func textIncludesSpeechAndAnnouncement() {
    let vm = viewModel(
        homework: [HomeworkItem(subject: "语文", text: "小作文")],
        speeches: [
            SpeechEntry(subject: "政治", students: ""),
            SpeechEntry(subject: "生物", students: "12号 13号"),
        ],
        announcements: [Announcement(id: 1, text: "国庆快乐！")]
    )
    let text = SlideText.plain(vm)
    #expect(text.hasPrefix("2026.10.1 星期四\n【作业】"))
    #expect(text.contains("【演讲提醒】\n生物：12号 13号"))
    #expect(!text.contains("政治："))
    #expect(text.contains("【公告】\n· 国庆快乐！"))
}

@Test func textSubmitOnlyMarksTitleAndDisplayDate() {
    let vm = viewModel(
        homework: [HomeworkItem(subject: "数学", text: "卷子", submitNext: true)],
        submitOnly: true
    )
    let text = SlideText.plain(vm)
    #expect(text.hasPrefix("2026.10.2 星期四 · 只要交的"))
    #expect(text.contains("数学：卷子（明天交）"))
}

@Test func textEmptyDayUsesGreeting() {
    let vm = viewModel(dayKind: .holiday(name: "国庆节"))
    #expect(SlideText.plain(vm).contains("国庆快乐"))

    let plain = viewModel()
    #expect(SlideText.plain(plain).contains("今天没有作业"))
}

@Test func textIgnoresBlankHomework() {
    let data = AppData()
    var day = Day()
    day.homework = [HomeworkItem(subject: "语文", text: "  "), HomeworkItem(subject: "语文", text: "抄写")]
    let vm = Schedule.viewModel(
        {
            var d = data
            d.days["2026-10-01"] = day
            return d
        }(),
        date: "2026-10-01",
        submitOnly: false
    )
    let text = SlideText.plain(vm)
    #expect(text.contains("语文：抄写"))
    #expect(!text.contains("1."))
}
