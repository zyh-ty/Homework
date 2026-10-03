import AppKit
import Foundation
import HomeworkKit
import Observation
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case edit, week, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit: return "编辑"
        case .week: return "课表总览"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .edit: return "square.and.pencil"
        case .week: return "calendar"
        case .settings: return "gearshape"
        }
    }
}

/// 编辑页里可以聚焦的条目（顺序即阅读顺序，Alt+数字/上下键依赖它）
enum FieldID: Hashable {
    case announcement(Int)
    case newAnnouncement
    case homework(String)
    case speech(String)
    case schedule(Int)
}

enum FieldSection: Int, CaseIterable {
    case announcement = 1, homework, speech, schedule

    var title: String {
        switch self {
        case .announcement: return "公告"
        case .homework: return "作业"
        case .speech: return "演讲提醒"
        case .schedule: return "课表"
        }
    }
}

struct FocusRequest: Equatable {
    var target: FieldID
    var tick: Int
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String?
}

@Observable
final class AppState {
    static let shared = AppState()
    /// 启动页（命令行 --page 可指定，便于截图/验证）
    static var initialPage: Page = .edit

    var data: AppData
    var dataDir: URL
    var today: String
    var viewDate: String
    var submitOnly: Bool
    var draft: Day
    var page: Page = AppState.initialPage
    var isPresenting = false
    var toast: Toast?
    var focusRequest: FocusRequest?
    var currentField: FieldID?
    var lastExportedImage: URL?
    var lastExportDate: Date?
    var saveState = "已保存"
    var showShortcutHelp = false
    /// 编辑页当前可聚焦条目的顺序（Alt+数字/上下键用）
    var fieldOrder: [FieldID] = []
    /// 系统日历里的节假日 / 调休
    let holidays = HolidayService()
    /// 已忽略的调休提醒（本次运行内）
    var dismissedMakeupReminders: Set<String> = []

    private var dirty = false
    private var imageDirty = false
    private var lastEdit = Date()
    private var lastImage = Date()
    private var lastLaunch: LaunchView?
    private var saveTimer: Timer?
    private var imageTimer: Timer?
    private var relocateTimer: Timer?
    private var holidayTimer: Timer?
    private var toastTimer: Timer?
    private var exporting = false

    private init() {
        let dir = Store.resolveDataDir()
        let (loaded, notice) = Store.loadOrRecover(dir)
        let stamp = Schedule.todayString()
        data = loaded
        dataDir = dir
        today = stamp
        let launch = Schedule.launchView(
            loaded,
            today: stamp,
            minutes: Schedule.minutesOfDay(Date()),
            holidays: holidays.table
        )
        viewDate = launch.date
        submitOnly = launch.submitOnly
        draft = loaded.days[launch.date] ?? Day()
        lastLaunch = launch
        try? Store.ensureDir(dir)
        if !FileManager.default.fileExists(atPath: Store.dataFile(dir).path) {
            saveNow()
        }
        if let notice {
            show(notice, symbol: "exclamationmark.triangle.fill")
        }
        startTimers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.holidays.refreshIfNeeded()
        }
    }

    // MARK: - 派生数据

    var viewModel: ViewModel {
        Schedule.viewModel(data, date: viewDate, submitOnly: submitOnly, holidays: holidays.table)
    }

    /// 页面日（作业所属日）的性质
    var pageDayKind: DayKind {
        HolidayRules.classify(viewDate, table: holidays.table, userDays: Set(data.days.keys))
    }

    /// 画面显示日的性质（「仅要交」时是下一上学日）
    var displayDayKind: DayKind { viewModel.dayKind }

    func dayKind(for date: String) -> DayKind {
        HolidayRules.classify(date, table: holidays.table, userDays: Set(data.days.keys))
    }

    /// 未来三周内「日历说是调休上课、但还没建过」的日期
    var pendingMakeupDays: [String] {
        HolidayRules.pendingMakeupDays(
            table: holidays.table,
            userDays: Set(data.days.keys),
            from: today,
            within: 21
        ).filter { !dismissedMakeupReminders.contains($0) }
    }

    /// 调休提醒：一键新增这一天并按「上周几的课」猜一个默认值
    func adoptMakeupDay(_ date: String) {
        guard data.days[date] == nil else { return }
        do {
            try addDay(date, copiedFrom: nil)
            setDate(date, submitOnly: false)
            show("\(Schedule.dotDate(date)) 已加入，请核对课表", symbol: "arrow.triangle.2.circlepath")
        } catch {
            show("新增失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
        }
    }

    /// 这一天是不是「不用上课」的休息日
    func isRestDay(_ date: String) -> Bool {
        dayKind(for: date).isRestDay
    }

    var skipHolidayHomework: Bool {
        get { UserDefaults.standard.object(forKey: "skipHolidayHomework") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "skipHolidayHomework") }
    }

    var mode: Binding<Bool> {
        Binding(get: { self.submitOnly }, set: { self.submitOnly = $0 })
    }

    var dayList: [String] {
        var set = Set(data.days.keys)
        set.insert(today)
        set.insert(Schedule.addDays(today, 1))
        return set.sorted()
    }

    var dayLabel: String {
        "\(Schedule.dotDate(viewDate)) \(Schedule.weekdayCN(viewDate))"
    }

    var backupCount: Int {
        Store.listBackups(dataDir).count
    }

    func slots(forDate date: String) -> [Slot] {
        Schedule.effectiveSchedule(data, date: date)
    }

    // MARK: - 页面/日期

    func apply(_ launch: LaunchView) {
        viewDate = launch.date
        submitOnly = launch.submitOnly
        draft = data.days[launch.date] ?? Day()
    }

    func goToday() {
        guard !isPresenting else { return }
        let launch = Schedule.launchView(
            data,
            today: Schedule.todayString(),
            minutes: Schedule.minutesOfDay(Date()),
            holidays: holidays.table
        )
        today = Schedule.todayString()
        apply(launch)
        lastLaunch = launch
        show("已回到今天（\(Schedule.dotDate(launch.date))\(launch.submitOnly ? " · 仅要交" : "")）", symbol: "location.fill")
    }

    func setDate(_ date: String, submitOnly newMode: Bool? = nil) {
        viewDate = date
        if let newMode { submitOnly = newMode }
        draft = data.days[date] ?? Day()
    }

    func stepDay(_ delta: Int) {
        guard !isPresenting else { return }
        let list = dayList
        guard !list.isEmpty else { return }
        let index = list.firstIndex(of: viewDate) ?? list.firstIndex(of: today) ?? 0
        let next = max(0, min(list.count - 1, index + delta))
        setDate(list[next], submitOnly: false)
    }

    // MARK: - 编辑

    func draftChanged() {
        data.days[viewDate] = draft
        touch()
    }

    func touch() {
        dirty = true
        lastEdit = Date()
        imageDirty = true
        saveState = "未保存"
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTimer?.invalidate()
        saveTimer = nil
        do {
            try Store.save(dataDir, data)
            dirty = false
            saveState = "已保存"
        } catch {
            show("保存失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
        }
    }

    func setAnnouncements(_ list: [Announcement]) {
        data.announcements = list
        touch()
    }

    func addAnnouncement(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        data.announcements.append(Announcement(id: data.nextAnnouncementID, text: trimmed))
        touch()
    }

    func setWeeklySchedule(_ rows: [[String]]) {
        data.weeklySchedule = Schedule.normalizeWeekly(rows)
        touch()
    }

    func updateSettings(_ settings: HomeworkKit.Settings) {
        var next = settings
        next.dataDir = data.settings.dataDir
        data.settings = next
        touch()
    }

    func addDay(_ date: String, copiedFrom: Int?) throws {
        guard Schedule.parse(date) != nil else { throw StoreError("日期格式不正确") }
        guard data.days[date] == nil else { throw StoreError("该日期已存在") }
        data.days[date] = Day(copiedFromWeekday: copiedFrom.flatMap { (0..<7).contains($0) ? $0 : nil })
        touch()
    }

    func deleteDay(_ date: String) {
        data.days.removeValue(forKey: date)
        touch()
        if viewDate == date {
            setDate(today, submitOnly: false)
        }
    }

    func setCopyFrom(_ date: String, weekday: Int?) {
        guard var day = data.days[date] else { return }
        day.copiedFromWeekday = weekday
        data.days[date] = day
        if viewDate == date { draft = day }
        touch()
    }

    // MARK: - 数据目录

    func chooseDataDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "迁移到此目录"
        panel.message = "选择新的数据目录，现有数据会被复制过去（旧目录保留）"
        panel.directoryURL = dataDir.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            saveNow()
            let migrated = try Store.migrate(from: dataDir, to: url)
            dataDir = migrated
            data.settings.dataDir = migrated.path
            touch()
            saveNow()
            show("数据目录已迁移到 \(migrated.path)", symbol: "folder.fill")
        } catch {
            show("迁移失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
        }
    }

    func revealDataDir() {
        NSWorkspace.shared.activateFileViewerSelecting([Store.dataFile(dataDir)])
    }

    func revealLastImage() {
        guard let url = lastExportedImage else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 放映

    var presentViewModel: ViewModel { viewModel }

    /// 由主窗口注入：打开/关闭放映窗口
    var openPresentWindow: (() -> Void)?
    var closePresentWindow: (() -> Void)?

    func startPresenting() {
        guard !isPresenting else { return }
        saveNow()
        isPresenting = true
        openPresentWindow?()
    }

    func stopPresenting() {
        guard isPresenting else { return }
        isPresenting = false
        closePresentWindow?()
    }

    // MARK: - 键盘

    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        if keyCode == 96 { // F5
            isPresenting ? stopPresenting() : startPresenting()
            return true
        }
        if keyCode == 53 { // Esc
            if isPresenting { stopPresenting(); return true }
            if page != .edit { page = .edit; return true }
            return false
        }
        if isPresenting { return false }

        let editing = NSApp.keyWindow?.firstResponder is NSTextView

        if flags.contains(.control) && keyCode == 36 { // Ctrl+Enter 标记当前条目
            toggleCurrentField()
            return true
        }
        if flags.contains(.option) {
            if let chars = event.charactersIgnoringModifiers, let n = Int(chars), (1...4).contains(n) {
                if let section = FieldSection(rawValue: n) {
                    page = .edit
                    focus(section: section, order: fieldOrder)
                }
                return true
            }
            if keyCode == 125 { moveFocus(1, order: fieldOrder); return true }
            if keyCode == 126 { moveFocus(-1, order: fieldOrder); return true }
        }
        if !editing && page == .edit {
            if keyCode == 123 { stepDay(-1); return true }
            if keyCode == 124 { stepDay(1); return true }
        }
        return false
    }

    // MARK: - 出图

    func exportImage(manual: Bool, forToday: Bool = false) {
        let vm = forToday ? Schedule.viewModel(data, date: today, submitOnly: false) : viewModel
        exportImage(vm: vm, manual: manual)
    }

    func exportImage(vm: ViewModel, manual: Bool) {
        guard !exporting else { return }
        exporting = true
        defer { exporting = false }
        let date = vm.displayDate
        let png = MainActor.assumeIsolated {
            SlideRenderer.png(vm: vm, showBadge: data.settings.showBadge)
        }
        guard let png else {
            if manual { show("生成图片失败", symbol: "exclamationmark.triangle.fill") }
            return
        }
        do {
            let url = try Store.exportImage(png, dir: dataDir, date: date)
            lastExportedImage = url
            lastExportDate = Date()
            imageDirty = false
            lastImage = Date()
            if manual {
                show("已生成 \(url.lastPathComponent)", symbol: "photo.fill")
            }
        } catch {
            if manual { show("出图失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill") }
        }
    }

    // MARK: - 定时任务

    private func startTimers() {
        imageTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.tickAutoImage()
        }
        relocateTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.tickRelocate()
        }
        holidayTimer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.holidays.refresh(silently: true)
        }
        if let holidayTimer { RunLoop.main.add(holidayTimer, forMode: .common) }
        if let imageTimer { RunLoop.main.add(imageTimer, forMode: .common) }
        if let relocateTimer { RunLoop.main.add(relocateTimer, forMode: .common) }
    }

    private func tickAutoImage() {
        guard imageDirty, !isPresenting else { return }
        let interval = TimeInterval(max(10, data.settings.imageIntervalSecs))
        guard Date().timeIntervalSince(lastImage) >= interval else { return }
        lastImage = Date()
        exportImage(manual: false)
    }

    private func tickRelocate() {
        guard !isPresenting else { return }
        let launch = Schedule.launchView(
            data,
            today: Schedule.todayString(),
            minutes: Schedule.minutesOfDay(Date()),
            holidays: holidays.table
        )
        defer { lastLaunch = launch }
        guard let previous = lastLaunch else { return }
        let crossed = launch.date != previous.date || launch.submitOnly != previous.submitOnly
        let followsAuto = viewDate == previous.date && submitOnly == previous.submitOnly
        guard crossed, followsAuto else { return }
        today = Schedule.todayString()
        apply(launch)
        show(launch.submitOnly ? "已切换到今天早上（仅显示要交）" : "已切换到今天（显示全部）", symbol: "clock.arrow.circlepath")
    }

    // MARK: - 提示

    func show(_ text: String, symbol: String? = nil) {
        toast = Toast(text: text, symbol: symbol)
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { [weak self] _ in
            self?.toast = nil
        }
    }

    // MARK: - 焦点导航

    func focus(section: FieldSection, order: [FieldID]) {
        guard let target = order.first(where: { id in
            switch (section, id) {
            case (.announcement, .announcement), (.announcement, .newAnnouncement): return true
            case (.homework, .homework): return true
            case (.speech, .speech): return true
            case (.schedule, .schedule): return true
            default: return false
            }
        }) else { return }
        request(target)
    }

    func moveFocus(_ delta: Int, order: [FieldID]) {
        guard !order.isEmpty else { return }
        let index = currentField.flatMap { order.firstIndex(of: $0) }
        let next: Int
        if let index {
            next = max(0, min(order.count - 1, index + delta))
        } else {
            next = delta > 0 ? 0 : order.count - 1
        }
        request(order[next])
    }

    private func request(_ id: FieldID) {
        currentField = id
        focusRequest = FocusRequest(target: id, tick: (focusRequest?.tick ?? 0) + 1)
    }

    func toggleCurrentField() {
        guard let id = currentField else { return }
        switch id {
        case .announcement(let idx):
            guard idx < data.announcements.count else { return }
            data.announcements[idx].done.toggle()
            touch()
        case .homework(let row):
            let parts = row.split(separator: "#")
            let subject = String(parts.first ?? "")
            let ordinal = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            let indices = draft.homework.indices.filter { draft.homework[$0].subject == subject }
            guard ordinal < indices.count else { return }
            draft.homework[indices[ordinal]].submitNext.toggle()
            draftChanged()
        default:
            break
        }
    }
}
