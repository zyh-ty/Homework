import AppKit
import HomeworkKit
import SwiftUI

struct SettingsPage: View {
    @Environment(AppState.self) private var state
    @State private var appearance = AppAppearance.current
    @State private var interval = 60
    @State private var cutoff = Date()
    @State private var showBadge = true
    @State private var newDate = Date()
    @State private var newCopyFrom = ""
    @State private var pendingDelete: String?
    @State private var loaded = false
    @State private var keepAwake = Presenter.shared.keepAwake
    @State private var lockSwitching = Presenter.shared.lockSwitching
    @State private var presentScreen = Presenter.shared.screenID
    @State private var screenTick = 0

    private let copyOptions: [(String, String)] = [
        ("", "按当天星期"),
        ("0", "上周一的课"),
        ("1", "上周二的课"),
        ("2", "上周三的课"),
        ("3", "上周四的课"),
        ("4", "上周五的课"),
    ]

    var body: some View {
        Form {
            Section("常规") {
                Picker("外观", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _, new in AppAppearance.current = new }

                LabeledContent("数据目录") {
                    HStack(spacing: 8) {
                        Text(state.dataDir.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(UI.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button("在访达中显示") { state.revealDataDir() }
                        Button("更换…") { state.chooseDataDir() }
                    }
                }

                LabeledContent("出图间隔") {
                    HStack(spacing: 8) {
                        TextField("", value: $interval, format: .number)
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: interval) { _, new in
                                save(interval: max(10, new))
                            }
                        Stepper("秒", value: $interval, in: 10...3600, step: 10)
                            .labelsHidden()
                            .onChange(of: interval) { _, new in
                                save(interval: max(10, new))
                            }
                        Text("修改后超过该时长自动生成家庭作业图片")
                            .hintStyle()
                    }
                }

                LabeledContent("早晨分界线") {
                    HStack(spacing: 8) {
                        DatePicker("", selection: $cutoff, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .onChange(of: cutoff) { _, new in
                                save(cutoff: DateFmt.hhmm.string(from: new))
                            }
                        Text("早于该时间打开自动进入「仅要交」")
                            .hintStyle()
                    }
                }

                Toggle("放映时显示班徽", isOn: $showBadge)
                    .onChange(of: showBadge) { _, new in
                        save(showBadge: new)
                    }
            }

            Section {
                Toggle("放映时不熄屏", isOn: $keepAwake)
                    .onChange(of: keepAwake) { _, new in
                        Presenter.shared.keepAwake = new
                        Presenter.shared.refresh()
                    }

                Toggle("放映时锁定切换（隐藏 Dock 与菜单栏，禁用 ⌘Tab）", isOn: $lockSwitching)
                    .onChange(of: lockSwitching) { _, new in
                        Presenter.shared.lockSwitching = new
                    }

                LabeledContent("放映屏幕") {
                    HStack(spacing: 8) {
                        Picker("", selection: $presentScreen) {
                            Text("自动（放映窗口所在屏幕）").tag(UInt32(0))
                            ForEach(NSScreen.screens, id: \.displayID) { screen in
                                Text(screen.localizedName).tag(screen.displayID)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                        .id(screenTick)
                        .onChange(of: presentScreen) { _, new in
                            Presenter.shared.screenID = new
                        }
                        Text("接投影后就固定用它；投影拔掉自动退回")
                            .hintStyle()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                    screenTick &+= 1
                    if Presenter.shared.forgetMissingScreen() { presentScreen = 0 }
                }
            } header: {
                Text("放映")
            } footer: {
                Text("这些设置只对本机生效，不写进共享的数据文件。")
                    .hintStyle()
            }

            Section {
                HStack(spacing: 10) {
                    DatePicker("日期", selection: $newDate, displayedComponents: .date)
                        .frame(width: 210)
                    Picker("课表来源", selection: $newCopyFrom) {
                        ForEach(copyOptions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                    .frame(width: 190)
                    Button("新增日期") { addDay() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
                ForEach(dayKeys, id: \.self) { day in
                    dayRow(day)
                }
            } header: {
                Text("天数管理")
            } footer: {
                Text("调休补课日在这里新增；「上哪天的课」决定该日课表模版的来源。")
                    .hintStyle()
            }

            Section {
                LabeledContent("状态") {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(holidayStatusColor)
                            .frame(width: 7, height: 7)
                        Text(state.holidays.status.text)
                            .font(.system(size: 12))
                        Spacer()
                        Button("重新读取") { state.holidays.refresh() }
                    }
                }
                LabeledContent("日历") {
                    HStack(spacing: 8) {
                        Text(state.holidays.calendarTitle ?? "未找到「中国大陆节假日」日历")
                            .hintStyle()
                        Spacer()
                        Button("打开日历 App") { state.holidays.openCalendarApp() }
                    }
                }
                LabeledContent("已收录") {
                    Text("\(state.holidays.holidayCount) 天假期 · \(state.holidays.workdayCount) 天调休上课")
                        .hintStyle()
                }
                LabeledContent("上次更新") {
                    Text(state.holidays.updatedAt.map { Self.stampFormatter.string(from: $0) } ?? "—")
                        .hintStyle()
                }
                Toggle("法定节假日 / 周末自动跳过作业", isOn: Binding(
                    get: { state.skipHolidayHomework },
                    set: { state.skipHolidayHomework = $0 }
                ))
                HStack {
                    Button("日历权限设置…") { state.holidays.openCalendarPrivacySettings() }
                    Spacer()
                }
            } header: {
                Text("节假日与调休")
            } footer: {
                Text("读取系统日历里的「中国大陆节假日」订阅日历：放假当天放映显示节日问候（当天没有作业时）；日历标注的调休上课日会提前提醒你新增这一天并确认上哪天的课。你自己建过的那一天永远算上学日，日历只会「扣掉」假期，不会跳过你建过的天、也不会凭空添加课。未授权时可在「系统设置 → 隐私与安全性 → 日历」里打开。")
                    .hintStyle()
            }

            Section("快捷键") {
                shortcutGrid
            }

            Section("关于") {
                LabeledContent("版本") {
                    Text("每日作业 · 原生 macOS 版 1.0")
                        .hintStyle()
                }
                LabeledContent("数据文件") {
                    Text("data.json（自动备份 \(state.backupCount) 份 · backups/）")
                        .hintStyle()
                }
                HStack {
                    Button("立即保存") {
                        state.saveNow()
                        state.show("已保存", symbol: "checkmark.circle.fill")
                    }
                    Button("生成今天的作业图片") {
                        state.exportImage(manual: true, forToday: true)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(UI.canvas)
        .contentMargins(.top, 18, for: .scrollContent)
        .onAppear(perform: load)
        .confirmationDialog(
            "删除 \(pendingDelete ?? "") ？",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let day = pendingDelete { state.deleteDay(day) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("该日期上填写的作业、演讲与调课都会被删除。")
        }
    }

    private var dayKeys: [String] { state.data.days.keys.sorted() }

    private var holidayStatusColor: Color {
        switch state.holidays.status {
        case .ready: return .green
        case .loading, .idle: return .orange
        case .denied, .failed: return .red
        }
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    @ViewBuilder
    private func dayRow(_ day: String) -> some View {
        HStack(spacing: 10) {
            Text("\(day)　\(Schedule.weekdayCN(day))")
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .frame(width: 170, alignment: .leading)
            Picker("", selection: Binding(
                get: { state.data.days[day]?.copiedFromWeekday.map(String.init) ?? "" },
                set: { value in
                    state.setCopyFrom(day, weekday: value.isEmpty ? nil : Int(value))
                }
            )) {
                ForEach(copyOptions, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 160)
            if day == state.viewDate {
                Text("正在编辑")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(UI.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(UI.accent.opacity(0.12)))
            }
            Spacer()
            Button(role: .destructive) {
                pendingDelete = day
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除这一天")
        }
    }

    private var shortcutGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                  alignment: .leading, spacing: 7) {
            shortcut([("⌥", "1~4")], "跳到 公告 / 作业 / 演讲 / 课表")
            shortcut([("↩", nil)], "在输入框里新建下一条")
            shortcut([("⌃", "↩")], "标记当前条目（明天交 / 完成）")
            shortcut([("⌥", "↑"), ("⌥", "↓")], "在条目之间上下切换")
            shortcut([("←", nil), ("→", nil)], "切换上一天 / 下一天")
            shortcut([("F5", nil)], "进入放映 / 退出放映")
            shortcut([("⌘", "Z")], "撤销；⇧⌘Z 重做")
            shortcut([("⇧⌘", "C")], "复制作业图片")
            shortcut([("⌥⌘", "C")], "复制文字版作业")
            shortcut([("⌘", "T")], "回到今天")
            shortcut([("⌘", "D")], "立即生成图片")
            shortcut([("⌘", "K")], "课表总览")
            shortcut([("⌘", "S")], "立即保存")
            shortcut([("⌘", ".")], "退出放映")
            shortcut([("Esc", nil)], "退出放映 / 返回编辑页")
        }
        .padding(.vertical, 2)
    }

    private func shortcut(_ keys: [(String, String?)], _ text: String) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, pair in
                if let second = pair.1 {
                    HStack(spacing: 2) {
                        KeyCap(text: pair.0)
                        Text("+").font(.system(size: 10)).foregroundStyle(UI.secondaryText)
                        KeyCap(text: second)
                    }
                } else {
                    KeyCap(text: pair.0)
                }
            }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .padding(.leading, 4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
        }
    }

    // MARK: - 读写

    private func load() {
        guard !loaded else { return }
        loaded = true
        let settings = state.data.settings
        interval = settings.imageIntervalSecs
        showBadge = settings.showBadge
        let minutes = Schedule.cutoffMinutes(settings.morningCutoff)
        cutoff = Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
        ) ?? Date()
        newDate = Schedule.parse(Schedule.addDays(state.today, 1)) ?? Date()
    }

    private func save(interval: Int? = nil, cutoff cutoffText: String? = nil, showBadge badge: Bool? = nil) {
        guard loaded else { return }
        var settings = state.data.settings
        if let interval { settings.imageIntervalSecs = interval }
        if let cutoffText { settings.morningCutoff = cutoffText }
        if let badge { settings.showBadge = badge }
        state.updateSettings(settings)
    }

    private func addDay() {
        let day = Schedule.format(newDate)
        do {
            try state.addDay(day, copiedFrom: newCopyFrom.isEmpty ? nil : Int(newCopyFrom))
            state.setDate(day, submitOnly: false)
            state.page = .edit
            state.show("已新增 \(day)", symbol: "calendar.badge.plus")
        } catch {
            state.show("新增失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
        }
    }
}
