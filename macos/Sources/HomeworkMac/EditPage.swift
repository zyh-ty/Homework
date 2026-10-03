import HomeworkKit
import SwiftUI

struct CardBox<Content: View>: View {
    let symbol: String
    let title: String
    var hint: String? = nil
    var badge: String? = nil
    var tint: Color = UI.accent
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tint.opacity(0.13))
                    )
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let badge {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.12)))
                }
                Spacer(minLength: 8)
                if let trailing {
                    trailing
                }
                if let hint {
                    Text(hint)
                        .hintStyle()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(UI.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(UI.cardStroke, lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}

/// 输入行样式：浅底 + 圆角，聚焦时描边高亮
struct FieldStyle: ViewModifier {
    var focused: Bool
    var tint: Color = UI.accent

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(UI.subtleFill.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(focused ? tint.opacity(0.75) : Color.clear, lineWidth: 1.4)
            )
    }
}

extension View {
    func fieldStyle(focused: Bool, tint: Color = UI.accent) -> some View {
        modifier(FieldStyle(focused: focused, tint: tint))
    }
}

struct EditPage: View {
    @Environment(AppState.self) private var state
    @FocusState private var focus: FieldID?

    private var vm: ViewModel { state.viewModel }

    var body: some View {
        VStack(spacing: 12) {
            if let reminder = state.pendingMakeupDays.first {
                makeupReminder(reminder)
            }
            if state.pageDayKind != .school {
                dayBanner(state.pageDayKind)
            }
            AnnouncementCard(focus: $focus)
                .frame(height: announcementHeight)
            HStack(alignment: .top, spacing: 12) {
                HomeworkCard(focus: $focus)
                VStack(spacing: 12) {
                    SpeechCard(focus: $focus)
                    ScheduleCard(focus: $focus)
                }
                .frame(width: 398)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(14)
        .onAppear { state.fieldOrder = fieldOrder }
        .onChange(of: fieldOrder) { _, new in state.fieldOrder = new }
        .onChange(of: focus) { _, new in state.currentField = new }
        .onChange(of: state.focusRequest) { _, request in
            guard let request else { return }
            focus = request.target
        }
    }

    /// 当天是节假日 / 周末 / 调休上课日时的提示条
    private func dayBanner(_ kind: DayKind) -> some View {
        let tint: Color = kind.holidayName != nil ? .orange : (kind.makeupName != nil ? UI.accent : .secondary)
        return HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Schedule.dotDate(state.viewDate))　\(Schedule.weekdayCN(state.viewDate))　\(bannerTitle(kind))")
                    .font(.system(size: 12.5, weight: .semibold))
                if let subtitle = kind.subtitle {
                    Text(subtitle).hintStyle()
                } else if kind.makeupName != nil {
                    Text("请核对课表是否需要调整；「上哪天的课」可在右侧课表卡或设置里选择").hintStyle()
                }
            }
            Spacer(minLength: 0)
            if kind.makeupName != nil {
                Menu("上哪天的课") {
                    Button("按当天星期") { state.setCopyFrom(state.viewDate, weekday: nil) }
                    ForEach(0..<5, id: \.self) { index in
                        Button(["上周一", "上周二", "上周三", "上周四", "上周五"][index] + "的课") {
                            state.setCopyFrom(state.viewDate, weekday: index)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 0.8))
    }

    private func bannerTitle(_ kind: DayKind) -> String {
        switch kind {
        case .holiday(let name): return "\(name) · 法定节假日"
        case .weekend: return "周末休息"
        case .makeup(let name): return "\(name) · 调休上课日"
        case .school: return ""
        }
    }

    /// 未来三周内「日历说是调休上课、但还没建过」的提醒
    private func makeupReminder(_ date: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(UI.accent)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(UI.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Schedule.dotDate(date))　\(Schedule.weekdayCN(date))是调休上课日")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("日历上标着要上课，建议提前新增这一天并确认上哪天的课").hintStyle()
            }
            Spacer(minLength: 0)
            Button("加入并核对") { state.adoptMakeupDay(date) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("忽略") { state.dismissedMakeupReminders.insert(date) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(UI.accent.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(UI.accent.opacity(0.22), lineWidth: 0.8))
    }

    /// 公告卡按条数自适应高度（最多显示 4 行，多出的在卡内滚动）
    private var announcementHeight: CGFloat {
        128 + CGFloat(min(4, state.data.announcements.count)) * 26
    }

    /// 阅读顺序：公告 → 作业 → 演讲 → 课表
    private var fieldOrder: [FieldID] {
        var order: [FieldID] = []
        order.append(contentsOf: state.data.announcements.indices.map { FieldID.announcement($0) })
        order.append(.newAnnouncement)
        for subject in HomeworkCard.subjects(state: state, suggestions: vm.homeworkSuggestions) {
            for row in HomeworkCard.rows(state: state, subject: subject) {
                order.append(.homework(row.id))
            }
        }
        for subject in SpeechCard.subjects(state: state, suggestions: vm.speechSuggestions) {
            order.append(.speech(subject))
        }
        for index in 0..<PERIODS {
            order.append(.schedule(index))
        }
        return order
    }
}

// MARK: - 公告

struct AnnouncementCard: View {
    @Environment(AppState.self) private var state
    @FocusState.Binding var focus: FieldID?
    @State private var newText = ""

    var body: some View {
        CardBox(
            symbol: "megaphone.fill",
            title: "公告",
            hint: "所有日期共用一份 · 勾选后放映不再显示 · ⌃↩ 切换完成",
            badge: "\(state.data.announcements.filter { !$0.done }.count) 条未完成",
            tint: .orange
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(state.data.announcements.enumerated()), id: \.element.id) { index, item in
                            row(index: index, item: item)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(UI.accent)
                    TextField("新公告，回车添加…", text: $newText)
                        .fieldStyle(focused: focus == .newAnnouncement)
                        .focused($focus, equals: .newAnnouncement)
                        .onSubmit(add)
                    Button("添加", action: add)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func row(index: Int, item: Announcement) -> some View {
        HStack(spacing: 9) {
            Toggle("", isOn: Binding(
                get: { item.done },
                set: { value in
                    guard index < state.data.announcements.count else { return }
                    state.data.announcements[index].done = value
                    state.touch()
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            TextField("公告内容", text: Binding(
                get: { index < state.data.announcements.count ? state.data.announcements[index].text : "" },
                set: { value in
                    guard index < state.data.announcements.count else { return }
                    state.data.announcements[index].text = value
                    state.touch()
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: item.done ? .regular : .medium))
            .strikethrough(item.done, color: UI.secondaryText)
            .foregroundStyle(item.done ? UI.secondaryText : .primary)
            .focused($focus, equals: .announcement(index))
            .onSubmit { focus = .newAnnouncement }

            Button {
                guard index < state.data.announcements.count else { return }
                state.data.announcements.remove(at: index)
                state.touch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(UI.secondaryText.opacity(0.55))
            }
            .buttonStyle(.borderless)
            .help("删除这条公告")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(focus == .announcement(index) ? UI.accent.opacity(0.07) : .clear)
        )
    }

    private func add() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state.addAnnouncement(text)
        newText = ""
        DispatchQueue.main.async { focus = .newAnnouncement }
    }
}

// MARK: - 作业

struct HomeworkCard: View {
    @Environment(AppState.self) private var state
    @FocusState.Binding var focus: FieldID?
    @State private var picked = ""

    struct Row: Identifiable, Hashable {
        let id: String
        let subject: String
        let index: Int?
    }

    static func subjects(state: AppState, suggestions: [String]) -> [String] {
        var out = suggestions
        for item in state.draft.homework where !out.contains(item.subject) {
            out.append(item.subject)
        }
        return out
    }

    static func rows(state: AppState, subject: String) -> [Row] {
        let indices = state.draft.homework.indices.filter { state.draft.homework[$0].subject == subject }
        if indices.isEmpty {
            return [Row(id: "\(subject)#0", subject: subject, index: nil)]
        }
        return indices.enumerated().map { ordinal, index in
            Row(id: "\(subject)#\(ordinal)", subject: subject, index: index)
        }
    }

    private var subjects: [String] {
        Self.subjects(state: state, suggestions: state.viewModel.homeworkSuggestions)
    }

    private var available: [String] {
        ALL_SUBJECTS.filter { !subjects.contains($0) }
    }

    var body: some View {
        CardBox(
            symbol: "book.closed.fill",
            title: "作业",
            hint: state.pageDayKind.isRestDay
                ? "今天放假，作业可留空；要布置假期作业也能直接填"
                : "回车加一条 · ⌃↩ 切换明天交 · 留空不显示",
            badge: state.viewModel.homework.isEmpty ? nil : "共 \(state.viewModel.homework.count) 条"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(subjects, id: \.self) { subject in
                            subjectBlock(subject)
                        }
                    }
                }
                if !available.isEmpty {
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(UI.accent)
                        Picker("", selection: $picked) {
                            Text("添加其他学科…").tag("")
                            ForEach(available, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        Button("添加") {
                            guard !picked.isEmpty else { return }
                            addEntry(picked)
                            picked = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(picked.isEmpty)
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func subjectBlock(_ subject: String) -> some View {
        let rows = Self.rows(state: state, subject: subject)
        HStack(alignment: .top, spacing: 10) {
            Text(subject)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(UI.accent)
                .frame(width: 62, alignment: .trailing)
                .padding(.top, 6)
            VStack(spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                    rowView(row, ordinal: position, count: rows.count)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    private func rowView(_ row: Row, ordinal: Int, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(count > 1 ? "\(ordinal + 1)" : "")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(UI.accent)
                .frame(width: 12, alignment: .trailing)

            TextField("作业内容…", text: textBinding(row))
                .fieldStyle(focused: focus == .homework(row.id))
                .focused($focus, equals: .homework(row.id))
                .onSubmit { addEntry(row.subject) }

            Toggle("明天交", isOn: submitBinding(row))
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))
                .help("这条作业明天交（⌃↩）")

            Button {
                remove(row)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(UI.secondaryText.opacity(0.5))
            }
            .buttonStyle(.borderless)
            .help("删除这条作业")
            .opacity(row.index == nil ? 0 : 1)
            .disabled(row.index == nil)

            Button {
                addEntry(row.subject)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UI.accent)
            }
            .buttonStyle(.borderless)
            .help("给「\(row.subject)」再加一条作业（回车）")
            .opacity(ordinal == count - 1 ? 1 : 0)
            .disabled(ordinal != count - 1)
        }
    }

    private func textBinding(_ row: Row) -> Binding<String> {
        Binding(
            get: {
                guard let index = row.index, index < state.draft.homework.count else { return "" }
                return state.draft.homework[index].text
            },
            set: { value in
                if let index = row.index, index < state.draft.homework.count {
                    state.draft.homework[index].text = value
                } else {
                    state.draft.homework.append(HomeworkItem(subject: row.subject, text: value))
                }
                state.draftChanged()
            }
        )
    }

    private func submitBinding(_ row: Row) -> Binding<Bool> {
        Binding(
            get: {
                guard let index = row.index, index < state.draft.homework.count else { return false }
                return state.draft.homework[index].submitNext
            },
            set: { value in
                if let index = row.index, index < state.draft.homework.count {
                    state.draft.homework[index].submitNext = value
                } else {
                    state.draft.homework.append(HomeworkItem(subject: row.subject, text: "", submitNext: value))
                }
                state.draftChanged()
            }
        )
    }

    private func addEntry(_ subject: String) {
        state.draft.homework.append(HomeworkItem(subject: subject, text: ""))
        state.draftChanged()
        let id = "\(subject)#\(Self.rows(state: state, subject: subject).count - 1)"
        DispatchQueue.main.async { focus = .homework(id) }
    }

    private func remove(_ row: Row) {
        guard let index = row.index, index < state.draft.homework.count else { return }
        state.draft.homework.remove(at: index)
        state.draftChanged()
    }
}

// MARK: - 演讲提醒

struct SpeechCard: View {
    @Environment(AppState.self) private var state
    @FocusState.Binding var focus: FieldID?
    @State private var picked = ""

    static func subjects(state: AppState, suggestions: [String]) -> [String] {
        var out = suggestions
        for entry in state.draft.speeches where !out.contains(entry.subject) {
            out.append(entry.subject)
        }
        return out
    }

    private var subjects: [String] {
        Self.subjects(state: state, suggestions: state.viewModel.speechSuggestions)
    }

    private var available: [String] {
        ALL_SUBJECTS.filter { !subjects.contains($0) }
    }

    var body: some View {
        CardBox(
            symbol: "mic.fill",
            title: "演讲提醒",
            hint: "按下一上学日课表预填",
            tint: state.viewModel.speechWarn ? .red : UI.accent
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if state.viewModel.speechWarn {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("演讲提醒未填写，放映时会醒目提示")
                            .font(.system(size: 11.5, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.red.opacity(0.10))
                    )
                }

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(subjects, id: \.self) { subject in
                            HStack(spacing: 8) {
                                Text(subject)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(UI.accent)
                                    .frame(width: 52, alignment: .trailing)
                                TextField("学号", text: binding(subject))
                                    .fieldStyle(focused: focus == .speech(subject))
                                    .focused($focus, equals: .speech(subject))
                                    .onSubmit { addNext() }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                if !available.isEmpty {
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(UI.accent)
                        Picker("", selection: $picked) {
                            Text("添加其他学科…").tag("")
                            ForEach(available, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        Button("添加") {
                            guard !picked.isEmpty else { return }
                            materialize(picked)
                            state.draftChanged()
                            picked = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(picked.isEmpty)
                        Spacer()
                    }
                }
            }
        }
    }

    @discardableResult
    private func materialize(_ subject: String) -> Int {
        if let index = state.draft.speeches.firstIndex(where: { $0.subject == subject }) {
            return index
        }
        state.draft.speeches.append(SpeechEntry(subject: subject, students: ""))
        return state.draft.speeches.count - 1
    }

    private func binding(_ subject: String) -> Binding<String> {
        Binding(
            get: { state.draft.speeches.first(where: { $0.subject == subject })?.students ?? "" },
            set: { value in
                let index = materialize(subject)
                state.draft.speeches[index].students = value
                state.draftChanged()
            }
        )
    }

    private func addNext() {
        guard let next = ALL_SUBJECTS.first(where: { !subjects.contains($0) }) else { return }
        materialize(next)
        state.draftChanged()
        DispatchQueue.main.async { focus = .speech(next) }
    }
}

// MARK: - 课表

struct ScheduleCard: View {
    @Environment(AppState.self) private var state
    @FocusState.Binding var focus: FieldID?

    private var baseIndex: Int {
        state.draft.copiedFromWeekday ?? (Schedule.weekdayIndex(state.viewDate) ?? 0)
    }

    private var title: String {
        let weekday = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][max(0, min(6, baseIndex))]
        return "课表（\(weekday)\(state.draft.copiedFromWeekday != nil ? " · 调休" : "")）"
    }

    private func base(_ period: Int) -> String {
        let rows = state.data.weeklySchedule
        guard baseIndex < rows.count, period < rows[baseIndex].count else { return "" }
        return rows[baseIndex][period]
    }

    private func override(_ period: Int) -> String {
        guard period < state.draft.scheduleOverride.count else { return "" }
        return state.draft.scheduleOverride[period] ?? ""
    }

    var body: some View {
        CardBox(
            symbol: "calendar",
            title: title,
            hint: "改自动标红 · 回车跳下一节",
            badge: changedCount > 0 ? "\(changedCount) 节调课" : nil,
            tint: changedCount > 0 ? .red : UI.accent,
            trailing: state.pageDayKind.makeupName != nil
                ? AnyView(
                    Menu(copyFromLabel) {
                        Button("按当天星期") { state.setCopyFrom(state.viewDate, weekday: nil) }
                        ForEach(0..<5, id: \.self) { index in
                            Button(["上周一", "上周二", "上周三", "上周四", "上周五"][index] + "的课") {
                                state.setCopyFrom(state.viewDate, weekday: index)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                )
                : nil
        ) {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(0..<PERIODS, id: \.self) { period in
                        HStack(spacing: 8) {
                            Text("\(period + 1)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(UI.secondaryText)
                                .frame(width: 16, alignment: .trailing)
                            TextField(base(period).isEmpty ? "（空）" : base(period), text: binding(period))
                                .fieldStyle(focused: focus == .schedule(period), tint: override(period).isEmpty ? UI.accent : .red)
                                .foregroundStyle(override(period).isEmpty ? Color.primary : Color.red)
                                .focused($focus, equals: .schedule(period))
                                .onSubmit { focusNext(period) }
                        }
                    }
                }
            }
        }
    }

    private var copyFromLabel: String {
        guard let index = state.draft.copiedFromWeekday, (0..<5).contains(index) else { return "按当天星期" }
        return ["上周一的课", "上周二的课", "上周三的课", "上周四的课", "上周五的课"][index]
    }

    private var changedCount: Int {
        (0..<PERIODS).filter { period in
            let value = override(period)
            return !value.isEmpty && value != base(period)
        }.count
    }

    private func binding(_ period: Int) -> Binding<String> {
        Binding(
            get: { override(period) },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                while state.draft.scheduleOverride.count < PERIODS {
                    state.draft.scheduleOverride.append(nil)
                }
                state.draft.scheduleOverride[period] = (trimmed.isEmpty || trimmed == base(period)) ? nil : trimmed
                state.draftChanged()
            }
        )
    }

    private func focusNext(_ period: Int) {
        guard period + 1 < PERIODS else { return }
        focus = .schedule(period + 1)
    }
}
