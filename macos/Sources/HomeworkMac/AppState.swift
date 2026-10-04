import AppKit
import Foundation
import HomeworkKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

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

    /// 撤销/重做：菜单项标题与可用性（@Observable 只跟踪属性，UndoHistory 内部变化要同步出来）
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoActionName = ""
    private(set) var redoActionName = ""

    private let history = UndoHistory()
    /// 上一次提交时的状态：touch() 在变更之后调用，用它拿到真正的「变更前」快照
    private var committed = DataSnapshot(data: AppData(), viewDate: "")
    private var dirty = false
    private var imageDirty = false
    private var lastEdit = Date()
    private var lastImage = Date()
    private var lastLaunch: LaunchView?
    private var saveTimer: Timer?
    private var imageTimer: Timer?
    private var cutoffTimer: Timer?
    private var holidayTimer: Timer?
    private var toastTimer: Timer?
    private var watcher: DataFileWatcher?
    private var externalRetry = 0
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
        committed = currentSnapshot
        try? Store.ensureDir(dir)
        if !FileManager.default.fileExists(atPath: Store.dataFile(dir).path) {
            saveNow()
        }
        if let notice {
            show(notice, symbol: "exclamationmark.triangle.fill")
        }
        watchDataDir(dir)
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

    /// 调休提醒：一键新增这一天，并按「最近一个上学日的星期几」猜一个默认课表来源
    func adoptMakeupDay(_ date: String) {
        guard data.days[date] == nil else { return }
        do {
            try addDay(date, copiedFrom: Schedule.defaultCopyFrom(data, date: date, holidays: holidays.table))
            setDate(date, submitOnly: false)
            show("\(Schedule.dotDate(date)) 已加入，请在课表卡核对上哪天的课", symbol: "arrow.triangle.2.circlepath")
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
        rebase()
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
        rebase()
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

    func draftChanged(_ name: String? = nil) {
        data.days[viewDate] = draft
        touch(name)
    }

    /// 每次变更的收口：先把「变更前」快照记进撤销栈，再落盘
    func touch(_ name: String? = nil) {
        if let name {
            history.record(committed, name: name, token: "cmd:\(name)")
        } else {
            history.record(committed, name: actionName, token: tokenKey)
        }
        committed = currentSnapshot
        syncHistoryFlags()
        markDirty()
    }

    private func markDirty() {
        dirty = true
        lastEdit = Date()
        imageDirty = true
        saveState = "未保存"
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
        scheduleAutoImage()
    }

    // MARK: - 撤销 / 重做

    var currentSnapshot: DataSnapshot {
        DataSnapshot(data: data, viewDate: viewDate)
    }

    /// 当前编辑点的名字（键盘导航与鼠标点击都会写 currentField）
    private var actionName: String {
        guard let field = currentField else { return "编辑当天内容" }
        switch field {
        case .announcement, .newAnnouncement: return "编辑公告"
        case .homework: return "编辑作业"
        case .speech: return "编辑演讲提醒"
        case .schedule: return "编辑课表"
        }
    }

    /// 合并键：同一个输入框内的连续编辑算一步，换字段或换天就断开
    private var tokenKey: String {
        guard let field = currentField else { return "day@\(viewDate)" }
        let key: String
        switch field {
        case .announcement(let index): key = "announcement#\(index)"
        case .newAnnouncement: key = "newAnnouncement"
        case .homework(let row): key = "homework#\(row)"
        case .speech(let subject): key = "speech#\(subject)"
        case .schedule(let period): key = "schedule#\(period)"
        }
        return "\(key)@\(viewDate)"
    }

    private func syncHistoryFlags() {
        canUndo = history.canUndo
        canRedo = history.canRedo
        undoActionName = history.undoName ?? ""
        redoActionName = history.redoName ?? ""
    }

    func undo() {
        guard let step = history.undo(current: currentSnapshot) else { return }
        restore(step.snapshot)
        show("已撤销「\(step.name)」", symbol: "arrow.uturn.backward")
    }

    func redo() {
        guard let step = history.redo(current: currentSnapshot) else { return }
        restore(step.snapshot)
        show("已重做「\(step.name)」", symbol: "arrow.uturn.forward")
    }

    /// 恢复整份数据与页面日；不记历史，否则撤销本身会被撤销
    private func restore(_ snapshot: DataSnapshot) {
        data = snapshot.data
        viewDate = snapshot.viewDate
        draft = data.days[snapshot.viewDate] ?? Day()
        committed = currentSnapshot
        history.breakCoalescing()
        syncHistoryFlags()
        markDirty()
    }

    /// 视图状态变化（切天、重新定位）：刷新基线，不产生历史
    private func rebase() {
        committed = currentSnapshot
        history.breakCoalescing()
    }

    func saveNow() {
        saveTimer?.invalidate()
        saveTimer = nil
        do {
            try Store.save(dataDir, data)
            dirty = false
            saveState = "已保存"
            watcher?.acknowledge()
        } catch {
            show("保存失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
        }
    }

    func setAnnouncements(_ list: [Announcement]) {
        data.announcements = list
        touch("编辑公告")
    }

    func addAnnouncement(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        data.announcements.append(Announcement(id: data.nextAnnouncementID, text: trimmed))
        touch("新增公告")
    }

    func setAnnouncementDone(_ index: Int, _ done: Bool) {
        guard index < data.announcements.count, data.announcements[index].done != done else { return }
        data.announcements[index].done = done
        touch("标记公告完成")
    }

    func setAnnouncementText(_ index: Int, _ text: String) {
        guard index < data.announcements.count, data.announcements[index].text != text else { return }
        data.announcements[index].text = text
        touch("编辑公告")
    }

    func removeAnnouncement(at index: Int) {
        guard index < data.announcements.count else { return }
        data.announcements.remove(at: index)
        touch("删除公告")
    }

    func setWeeklySchedule(_ rows: [[String]]) {
        data.weeklySchedule = Schedule.normalizeWeekly(rows)
        touch("修改周课表模版")
    }

    func updateSettings(_ settings: HomeworkKit.Settings) {
        var next = settings
        next.dataDir = data.settings.dataDir
        data.settings = next
        touch("修改设置")
    }

    func addDay(_ date: String, copiedFrom: Int?) throws {
        guard Schedule.parse(date) != nil else { throw StoreError("日期格式不正确") }
        guard data.days[date] == nil else { throw StoreError("该日期已存在") }
        data.days[date] = Day(copiedFromWeekday: copiedFrom.flatMap { (0..<7).contains($0) ? $0 : nil })
        touch("新增天数")
    }

    func deleteDay(_ date: String) {
        data.days.removeValue(forKey: date)
        touch("删除天数")
        if viewDate == date {
            setDate(today, submitOnly: false)
        }
    }

    func setCopyFrom(_ date: String, weekday: Int?) {
        guard var day = data.days[date] else { return }
        day.copiedFromWeekday = weekday
        data.days[date] = day
        if viewDate == date { draft = day }
        touch("调整调休来源")
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
            touch("迁移数据目录")
            saveNow()
            // 文件已经搬过去了，撤销指针没有意义：历史从新目录重新开始
            history.clear()
            syncHistoryFlags()
            rebase()
            watchDataDir(migrated)
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
        Presenter.shared.begin()
        openPresentWindow?()
    }

    func stopPresenting() {
        guard isPresenting else { return }
        isPresenting = false
        Presenter.shared.end()
        closePresentWindow?()
        scheduleAutoImage()
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

    /// 自动出图固定「今天 · 全部」；手动出图导出当前屏幕所见（页面日 + 当前模式）
    @discardableResult
    func exportImage(manual: Bool, forToday: Bool = false) -> URL? {
        let vm = forToday
            ? Schedule.viewModel(data, date: today, submitOnly: false, holidays: holidays.table)
            : viewModel
        return exportImage(vm: vm, manual: manual)
    }

    @discardableResult
    func exportImage(vm: ViewModel, manual: Bool) -> URL? {
        guard !exporting else { return nil }
        exporting = true
        defer { exporting = false }
        // 文件名用页面日（作业所属的那一天），「仅要交」时画面日期是下一上学日，不作为文件名
        let date = vm.date
        let png = MainActor.assumeIsolated {
            SlideRenderer.png(vm: vm, showBadge: data.settings.showBadge)
        }
        guard let png else {
            if manual { show("生成图片失败", symbol: "exclamationmark.triangle.fill") }
            return nil
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
            return url
        } catch {
            if manual { show("出图失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill") }
            return nil
        }
    }

    // MARK: - 复制 / 分享 / 拖拽

    /// 当前屏幕所见的 PNG（页面日 + 当前模式）
    func slidePNG() -> Data? {
        MainActor.assumeIsolated {
            SlideRenderer.png(vm: viewModel, showBadge: data.settings.showBadge)
        }
    }

    func copySlideImage() {
        guard let png = slidePNG() else {
            show("生成图片失败", symbol: "exclamationmark.triangle.fill")
            return
        }
        Clipboard.copy(png: png)
        show("已复制图片，可直接粘到微信", symbol: "doc.on.clipboard")
    }

    func copySlideText() {
        Clipboard.copy(text: SlideText.plain(viewModel), rich: SlideRichText.attributed(viewModel))
        show("已复制文字版作业", symbol: "text.quote")
    }

    /// 分享：先落盘成 PNG（AirDrop / 信息要的是文件），再弹分享面板
    func shareSlide() {
        guard let url = exportImage(vm: viewModel, manual: false) else {
            show("生成图片失败", symbol: "exclamationmark.triangle.fill")
            return
        }
        Sharing.present([url])
    }

    /// 拖拽源：直接把 PNG 数据交给微信等接收方，不用先找文件
    func slideItemProvider() -> NSItemProvider {
        let png = slidePNG()
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(png, nil)
            return nil
        }
        return provider
    }

    // MARK: - 定时任务与系统事件

    private func startTimers() {
        holidayTimer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.holidays.refresh(silently: true)
        }
        if let holidayTimer { RunLoop.main.add(holidayTimer, forMode: .common) }
        scheduleAutoImage()
        scheduleCutoff()
        observeSystemEvents()
    }

    /// 自动出图改成一次性定时：最后一次编辑满 interval 秒才出图，不再每 2 秒轮询
    private func scheduleAutoImage() {
        imageTimer?.invalidate()
        imageTimer = nil
        guard imageDirty, !isPresenting else { return }
        let interval = TimeInterval(max(10, data.settings.imageIntervalSecs))
        let delay = max(0.5, lastImage.addingTimeInterval(interval).timeIntervalSinceNow)
        let timer = Timer(fire: Date().addingTimeInterval(delay), interval: 0, repeats: false) { [weak self] _ in
            self?.fireAutoImage()
        }
        imageTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func fireAutoImage() {
        imageTimer = nil
        guard imageDirty, !isPresenting else { return }
        let interval = TimeInterval(max(10, data.settings.imageIntervalSecs))
        guard Date().timeIntervalSince(lastImage) >= interval else {
            scheduleAutoImage()
            return
        }
        exportImage(manual: false, forToday: true)
    }

    /// 早晨分界线只在这一刻需要重算：排一次性定时，不轮询
    private func scheduleCutoff() {
        cutoffTimer?.invalidate()
        let fire = Schedule.nextCutoff(after: Date(), cutoff: data.settings.morningCutoff)
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            self?.refreshFromClock()
        }
        cutoffTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// 跨天 / 合盖唤醒 / 改时钟或时区：重算「今天」与自动定位
    private func observeSystemEvents() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshFromClock()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshFromClock()
        }
    }

    private func refreshFromClock() {
        today = Schedule.todayString()
        tickRelocate()
        scheduleCutoff()
        scheduleAutoImage()
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

    // MARK: - 数据文件外部改动

    private func watchDataDir(_ dir: URL) {
        watcher?.stop()
        let watcher = DataFileWatcher(dir: dir) { [weak self] in
            self?.externalChangeDetected()
        }
        self.watcher = watcher
        watcher.start()
    }

    private func externalChangeDetected() {
        // 磁盘内容与内存一致（多半是自己刚保存引出的目录事件）→ 只刷新基线，不打扰
        if !dirty,
           let onDisk = try? Store.load(dataDir),
           let theirs = try? Store.encode(onDisk),
           let mine = try? Store.encode(data),
           theirs == mine {
            externalRetry = 0
            watcher?.acknowledge()
            return
        }
        guard !dirty else {
            show("数据文件已在外部改动；本机还有未保存的修改，可用「从磁盘重新载入」载入", symbol: "exclamationmark.triangle.fill")
            return
        }
        reloadFromDisk(force: true)
    }

    /// 重新从磁盘载入（外部改动 / 手动 ⌘R）；force = 放弃本机未保存的修改
    func reloadFromDisk(force: Bool = false) {
        if dirty && !force {
            show("本机还有未保存的修改，未载入外部改动", symbol: "exclamationmark.triangle.fill")
            return
        }
        guard let loaded = try? Store.load(dataDir) else {
            // 共享目录/网盘上可能正好读到写了一半的文件：重试几次，别用「恢复」去覆盖主文件
            guard externalRetry < 3 else {
                externalRetry = 0
                show("外部改动暂时读不出来（可能正在同步），稍后会自动再试", symbol: "exclamationmark.triangle.fill")
                return
            }
            externalRetry += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.externalChangeDetected()
            }
            return
        }
        externalRetry = 0
        data = loaded
        draft = data.days[viewDate] ?? Day()
        committed = currentSnapshot
        history.clear()
        syncHistoryFlags()
        imageDirty = true
        scheduleAutoImage()
        show("已重新载入数据文件", symbol: "arrow.clockwise")
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
            setAnnouncementDone(idx, !data.announcements[idx].done)
        case .homework(let row):
            let parts = row.split(separator: "#")
            let subject = String(parts.first ?? "")
            let ordinal = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            let indices = draft.homework.indices.filter { draft.homework[$0].subject == subject }
            guard ordinal < indices.count else { return }
            draft.homework[indices[ordinal]].submitNext.toggle()
            draftChanged("标记明天交")
        default:
            break
        }
    }
}
