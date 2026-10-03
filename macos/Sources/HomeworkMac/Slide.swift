import AppKit
import HomeworkKit
import SwiftUI

/// 放映画面（同时也是导出 PNG 的画面）：固定 1920×1080 设计尺寸，按比例缩放绘制
struct SlideView: View {
    let vm: ViewModel
    let showBadge: Bool
    let size: CGSize
    /// 法定节假日/周末且当天没有作业时，用节日问候替代作业列表
    var showRestDayGreeting: Bool = true

    private var k: CGFloat { size.width / Slide.w }

    private var contentWidth: CGFloat { Slide.w - Slide.margin * 2 }
    private var leftWidth: CGFloat { 1330 }
    private var rightWidth: CGFloat { contentWidth - leftWidth - Slide.gap }

    var body: some View {
        ZStack {
            background
            VStack(spacing: k * Slide.gap) {
                header
                if !vm.announcements.isEmpty {
                    announcementBar
                }
                HStack(alignment: .top, spacing: k * Slide.gap) {
                    homeworkCard
                        .frame(width: k * leftWidth)
                    VStack(spacing: k * Slide.gap) {
                        scheduleCard
                            .frame(height: k * scheduleCardHeight)
                        speechCard
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: k * rightWidth)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(k * Slide.margin)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .light)
    }

    // MARK: - 背景

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Slide.bgTop, Slide.bgBottom], startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.36, green: 0.60, blue: 0.94).opacity(0.30), .clear],
                        center: .center, startRadius: 0, endRadius: k * 420
                    )
                )
                .frame(width: k * 840, height: k * 840)
                .offset(x: -k * 700, y: -k * 470)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.35, green: 0.78, blue: 0.85).opacity(0.22), .clear],
                        center: .center, startRadius: 0, endRadius: k * 380
                    )
                )
                .frame(width: k * 760, height: k * 760)
                .offset(x: k * 720, y: k * 380)
        }
        .ignoresSafeArea()
    }

    private func cardSurface<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: k * Slide.cardRadius, style: .continuous)
                    .fill(Slide.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: k * Slide.cardRadius, style: .continuous)
                    .strokeBorder(Slide.cardStroke, lineWidth: k * 1.6)
            )
            .shadow(color: Color(red: 0.13, green: 0.22, blue: 0.38).opacity(0.10), radius: k * 22, y: k * 8)
    }

    // MARK: - 顶部标题带

    private var header: some View {
        HStack(spacing: k * 22) {
            if showBadge, let badge = Badge.image {
                Image(nsImage: badge)
                    .resizable()
                    .scaledToFit()
                    .frame(width: k * 62, height: k * 62)
                    .padding(k * 14)
                    .background(
                        RoundedRectangle(cornerRadius: k * 26, style: .continuous)
                            .fill(.white.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: k * 26, style: .continuous)
                            .strokeBorder(.white.opacity(0.28), lineWidth: k * 1.4)
                    )
            }
            VStack(alignment: .leading, spacing: k * 3) {
                Text("每日作业")
                    .font(.system(size: k * 46, weight: .bold))
                    .foregroundStyle(.white)
                Text("DAILY HOMEWORK")
                    .font(.system(size: k * 13, weight: .semibold, design: .rounded))
                    .tracking(k * 3.4)
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: k * 2) {
                Text(Slide.dot(vm.displayDate))
                    .font(.system(size: k * 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(vm.weekday)
                    .font(.system(size: k * 27, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .padding(.horizontal, k * 28)
        .frame(maxWidth: .infinity)
        .frame(height: k * 132)
        .background(bandBackground)
        .clipShape(RoundedRectangle(cornerRadius: k * 34, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: k * 34, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: k * 1.4)
        )
        .shadow(color: Slide.bandBottom.opacity(0.35), radius: k * 24, y: k * 10)
    }

    private var bandBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Slide.bandTop, Slide.bandBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.13))
                .frame(width: k * 360, height: k * 360)
                .offset(x: k * 640, y: -k * 96)
                .blur(radius: k * 26)
            Circle()
                .strokeBorder(.white.opacity(0.12), lineWidth: k * 2)
                .frame(width: k * 210, height: k * 210)
                .offset(x: k * 430, y: k * 74)
        }
    }

    // MARK: - 公告条

    private var announcementBar: some View {
        HStack(alignment: .center, spacing: k * 20) {
            Image(systemName: "megaphone.fill")
                .font(.system(size: k * 28, weight: .semibold))
                .foregroundStyle(Slide.annText)
                .frame(width: k * 62, height: k * 62)
                .background(Circle().fill(.white.opacity(0.6)))
            VStack(alignment: .leading, spacing: k * 10) {
                ForEach(vm.announcements) { item in
                    HStack(alignment: .firstTextBaseline, spacing: k * 14) {
                        Circle()
                            .fill(Slide.annText.opacity(0.6))
                            .frame(width: k * 13, height: k * 13)
                        Text(item.text)
                            .font(.system(size: k * 44, weight: .bold))
                            .foregroundStyle(Slide.annText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, k * 26)
        .padding(.vertical, k * 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Slide.amberTop, Slide.amberBottom], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: k * 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: k * 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: k * 1.6)
        )
        .shadow(color: Slide.amberBottom.opacity(0.45), radius: k * 18, y: k * 8)
    }

    // MARK: - 家庭作业

    struct HwSub: Identifiable {
        var id: String { label }
        let label: String
        var entries: [HomeworkItem]
    }

    struct HwGroup: Identifiable {
        var id: String { subjects.map(\.label).joined(separator: "|") }
        var subjects: [HwSub]
    }

    /// 学科分组：英语A/英语B 合占一个编号，位置取第一个英语出现处
    var groups: [HwGroup] {
        var order: [String] = []
        var bySubject: [String: [HomeworkItem]] = [:]
        for item in vm.homework {
            if bySubject[item.subject] == nil {
                order.append(item.subject)
                bySubject[item.subject] = []
            }
            bySubject[item.subject]?.append(item)
        }
        var out: [HwGroup] = []
        var englishIndex: Int?
        for label in order {
            let sub = HwSub(label: label, entries: bySubject[label] ?? [])
            if label == "英语A" || label == "英语B" {
                if let index = englishIndex {
                    out[index].subjects.append(sub)
                } else {
                    englishIndex = out.count
                    out.append(HwGroup(subjects: [sub]))
                }
            } else {
                out.append(HwGroup(subjects: [sub]))
            }
        }
        return out
    }

    private var homeworkCard: some View {
        cardSurface {
            VStack(alignment: .leading, spacing: k * 14) {
                panelHeader(
                    symbol: "book.closed.fill",
                    title: vm.submitOnly ? "今天要交的作业" : "家庭作业",
                    badge: vm.submitOnly ? "来自 \(Slide.dot(vm.homeworkDate))" : "共 \(vm.homework.count) 项"
                )
                Divider().overlay(Slide.cardStroke)
                if isRestDayGreeting {
                    restDayGreeting
                } else if groups.isEmpty {
                    emptyState(
                        symbol: "checkmark.circle",
                        text: vm.submitOnly ? "今天没有要交的作业" : "今天还没有作业"
                    )
                } else {
                    homeworkRows
                }
            }
            .padding(k * 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var isRestDayGreeting: Bool {
        showRestDayGreeting && vm.homework.isEmpty && vm.dayKind.isRestDay
    }

    /// 假期/周末的大字问候
    @ViewBuilder
    private var restDayGreeting: some View {
        let holiday = vm.dayKind.holidayName != nil
        let colors: [Color] = holiday
            ? [Color(red: 0.98, green: 0.62, blue: 0.20), Color(red: 0.85, green: 0.16, blue: 0.16)]
            : [Color(red: 0.35, green: 0.62, blue: 0.94), Color(red: 0.13, green: 0.44, blue: 0.72)]
        VStack(spacing: k * 30) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: k * 156, height: k * 156)
                    .shadow(color: colors[1].opacity(0.35), radius: k * 26, y: k * 10)
                Image(systemName: vm.dayKind.symbol)
                    .font(.system(size: k * 68, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(vm.dayKind.greeting ?? "")
                .font(.system(size: k * 104, weight: .heavy))
                .foregroundStyle(
                    LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let subtitle = vm.dayKind.subtitle {
                Text(subtitle)
                    .font(.system(size: k * 34, weight: .medium))
                    .foregroundStyle(Slide.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    struct HwLayout {
        var size: CGFloat
        var columns: Int
        var spacing: CGFloat
    }

    /// 作业卡正文可用高度
    private var homeworkAvailable: CGFloat {
        contentAvailable - 26 * 2 - 78
    }

    private func textWidth(columns: Int) -> CGFloat {
        let columnWidth = (leftWidth - 26 * 2 - (columns == 1 ? 0 : CGFloat(columns - 1) * 26)) / CGFloat(columns)
        // 单列：编号 + 学科标签列 + 「明天交」胶囊；双列：编号 + 标签跟在正文前 + 胶囊
        return columns == 1 ? columnWidth - 56 - 18 - 150 - 12 - 150 : columnWidth - 46 - 14 - 140
    }

    private func groupHeight(_ group: HwGroup, size: CGFloat, columns: Int) -> CGFloat {
        var block: CGFloat = 0
        for sub in group.subjects {
            for item in sub.entries {
                let lines = TextMeasure.lines(item.text, size: size, width: textWidth(columns: columns))
                block += CGFloat(lines) * size * 1.28 + 6
            }
        }
        return max(block, 56)
    }

    private func columnHeights(_ size: CGFloat, columns: Int) -> [CGFloat] {
        if columns == 1 {
            return [groups.reduce(0) { $0 + groupHeight($1, size: size, columns: 1) }]
        }
        var heights: [CGFloat] = [0, 0]
        for group in groups {
            let height = groupHeight(group, size: size, columns: 2)
            if heights[0] <= heights[1] {
                heights[0] += height
            } else {
                heights[1] += height
            }
        }
        return heights
    }

    /// 一列放不下就拆两列；字号在 56…24 之间挑能放下的最大者
    var homeworkLayout: HwLayout {
        let available = homeworkAvailable
        for size in [CGFloat(56), 52, 48, 44, 40, 36, 32, 30, 28] {
            let need = columnHeights(size, columns: 1)[0]
            if need <= available {
                let slack = available - need
                let spacing = groups.count > 1 ? min(58, max(16, slack / CGFloat(groups.count - 1))) : 22
                return HwLayout(size: size, columns: 1, spacing: spacing)
            }
        }
        for size in [CGFloat(44), 40, 36, 32, 30, 28, 26, 24, 22] {
            let heights = columnHeights(size, columns: 2)
            let need = heights.max() ?? 0
            if need <= available {
                let spacing = min(46, max(14, (available - need) / 6))
                return HwLayout(size: size, columns: 2, spacing: spacing)
            }
        }
        return HwLayout(size: 22, columns: 2, spacing: 12)
    }

    @ViewBuilder
    private var homeworkRows: some View {
        let layout = homeworkLayout
        if layout.columns == 1 {
            groupColumn(numbered(groups, from: 1), layout: layout)
        } else {
            let split = balancedColumns()
            HStack(alignment: .top, spacing: k * 26) {
                groupColumn(numbered(split.0, from: 1), layout: layout)
                groupColumn(numbered(split.1, from: split.0.count + 1), layout: layout)
            }
        }
    }

    private func balancedColumns() -> ([HwGroup], [HwGroup]) {
        var left: [HwGroup] = []
        var right: [HwGroup] = []
        var heights: [CGFloat] = [0, 0]
        let size = homeworkLayout.size
        for group in groups {
            let height = groupHeight(group, size: size, columns: 2)
            if heights[0] <= heights[1] {
                left.append(group)
                heights[0] += height
            } else {
                right.append(group)
                heights[1] += height
            }
        }
        return (left, right)
    }

    private func numbered(_ list: [HwGroup], from start: Int) -> [(Int, HwGroup)] {
        list.enumerated().map { (start + $0.offset, $0.element) }
    }

    private func groupColumn(_ items: [(Int, HwGroup)], layout: HwLayout) -> some View {
        VStack(alignment: .leading, spacing: k * layout.spacing) {
            ForEach(items, id: \.1.id) { number, group in
                groupRow(number: number, group: group, layout: layout)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func groupRow(number: Int, group: HwGroup, layout: HwLayout) -> some View {
        if layout.columns == 2 {
            compactGroupRow(number: number, group: group, layout: layout)
        } else {
            alignedGroupRow(number: number, group: group, layout: layout)
        }
    }

    /// 双列：学科标签跟在正文前，横向更省空间
    private func compactGroupRow(number: Int, group: HwGroup, layout: HwLayout) -> some View {
        let size = layout.size
        return HStack(alignment: .top, spacing: k * 14) {
            compactBadge(number, size: size)
            VStack(alignment: .leading, spacing: k * 7) {
                ForEach(group.subjects) { sub in
                    ForEach(Array(sub.entries.enumerated()), id: \.offset) { entryIndex, item in
                        HStack(alignment: .top, spacing: k * 8) {
                            if sub.entries.count > 1 {
                                Text("\(entryIndex + 1)")
                                    .font(.system(size: k * size * 0.78, weight: .heavy, design: .rounded))
                                    .foregroundStyle(entryIndex == 0 ? Slide.blue : Slide.gray)
                                    .padding(.top, k * size * 0.14)
                            }
                            Text("\(entryIndex == 0 ? sub.label + "：" : "")")
                                .font(.system(size: k * size, weight: .bold))
                                .foregroundStyle(Slide.blue)
                                + Text(item.text)
                                .font(.system(size: k * size))
                                .foregroundStyle(Slide.text)
                            if item.submitNext && !vm.submitOnly {
                                submitTag(size * 0.9)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func compactBadge(_ number: Int, size: CGFloat) -> some View {
        Text("\(number)")
            .font(.system(size: k * size * 0.72, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: k * 46, height: k * 46)
            .background(
                RoundedRectangle(cornerRadius: k * 15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.36, green: 0.58, blue: 0.87), Slide.blue],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
    }

    private func alignedGroupRow(number: Int, group: HwGroup, layout: HwLayout) -> some View {
        let size = layout.size
        return HStack(alignment: .top, spacing: k * 18) {
            orderBadge(number)
            Grid(alignment: .topLeading, horizontalSpacing: k * 12, verticalSpacing: k * 8) {
                ForEach(group.subjects) { sub in
                    ForEach(Array(sub.entries.enumerated()), id: \.offset) { entryIndex, item in
                        GridRow(alignment: .top) {
                            Text(entryIndex == 0 ? "\(sub.label)：" : "")
                                .font(.system(size: k * size, weight: .bold))
                                .foregroundStyle(Slide.blue)
                                .fixedSize()
                            HStack(alignment: .top, spacing: k * 12) {
                                if sub.entries.count > 1 {
                                    Text("\(entryIndex + 1)")
                                        .font(.system(size: k * size * 0.78, weight: .heavy, design: .rounded))
                                        .foregroundStyle(entryIndex == 0 ? Slide.blue : Slide.gray)
                                        .padding(.top, k * size * 0.16)
                                }
                                Text(item.text)
                                    .font(.system(size: k * size))
                                    .foregroundStyle(Slide.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .layoutPriority(1)
                                if item.submitNext && !vm.submitOnly {
                                    submitTag(size)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func orderBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: k * 32, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: k * 56, height: k * 56)
            .background(
                RoundedRectangle(cornerRadius: k * 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.36, green: 0.58, blue: 0.87), Slide.blue],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .shadow(color: Slide.blue.opacity(0.28), radius: k * 8, y: k * 3)
    }

    private func submitTag(_ size: CGFloat) -> some View {
        Text("明天交")
            .font(.system(size: k * size * 0.58, weight: .bold))
            .foregroundStyle(Slide.orange)
            .padding(.horizontal, k * 14)
            .padding(.vertical, k * 7)
            .background(Capsule().fill(Slide.orangeSoft))
            .overlay(Capsule().strokeBorder(Slide.orange.opacity(0.55), lineWidth: k * 2))
            .padding(.top, k * size * 0.14)
            .fixedSize()
    }

    // MARK: - 课表

    private var scheduleEntries: [(index: Int, slot: Slot)] {
        vm.slots.enumerated().compactMap { i, slot in
            slot.name.isEmpty ? nil : (i + 1, slot)
        }
    }

    /// 课表卡高度：按内容需要，并适当吃掉多余空间
    private var scheduleCardHeight: CGFloat {
        let rows = max(1, Int(ceil(Double(scheduleEntries.count) / 2.0)))
        let natural = 48 + 52 + 14 + 2 + Double(rows) * 42 + Double(max(0, rows - 1)) * 12 + 12
        let allowed = max(170, contentAvailable - Slide.gap - 150)
        return min(allowed, natural * 1.34)
    }

    private var scheduleCard: some View {
        let entries = scheduleEntries
        let rows = max(1, Int(ceil(Double(entries.count) / 2.0)))
        return cardSurface {
            VStack(alignment: .leading, spacing: k * 12) {
                panelHeader(symbol: "calendar", title: "今日课表", badge: "\(entries.count) 节")
                Divider().overlay(Slide.cardStroke)
                if entries.isEmpty {
                    emptyState(symbol: "sun.max", text: "今日无课")
                } else {
                    VStack(spacing: 0) {
                        ForEach(0..<rows, id: \.self) { row in
                            HStack(spacing: k * 20) {
                                scheduleCell(entries.indices.contains(row) ? entries[row] : nil)
                                scheduleCell(entries.indices.contains(row + rows) ? entries[row + rows] : nil)
                            }
                            if row < rows - 1 {
                                Spacer(minLength: k * 8)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(k * 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func scheduleCell(_ entry: (index: Int, slot: Slot)?) -> some View {
        if let entry {
            HStack(spacing: k * 12) {
                Text("\(entry.index)")
                    .font(.system(size: k * 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(entry.slot.changed ? .white : Slide.gray)
                    .frame(width: k * 30, height: k * 30)
                    .background(
                        RoundedRectangle(cornerRadius: k * 9, style: .continuous)
                            .fill(entry.slot.changed ? AnyShapeStyle(Slide.red) : AnyShapeStyle(Slide.blueSoft))
                    )
                Text(entry.slot.name)
                    .font(.system(size: k * 33, weight: .bold))
                    .foregroundStyle(entry.slot.changed ? Slide.red : Slide.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: k * 30)
        }
    }

    // MARK: - 演讲提醒

    private var speechCard: some View {
        let entries = vm.speeches.filter { !$0.students.trimmingCharacters(in: .whitespaces).isEmpty }
        return cardSurface {
            VStack(alignment: .leading, spacing: k * 12) {
                panelHeader(symbol: "mic.fill", title: "演讲提醒", badge: entries.isEmpty ? nil : "\(entries.count) 项")
                Divider().overlay(Slide.cardStroke)
                if entries.isEmpty {
                    HStack(spacing: k * 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: k * 30, weight: .semibold))
                        Text("演讲提醒未填写")
                            .font(.system(size: k * 32, weight: .bold))
                    }
                    .foregroundStyle(Slide.red)
                    .padding(.horizontal, k * 22)
                    .padding(.vertical, k * 18)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: k * 20, style: .continuous).fill(Slide.redSoft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: k * 20, style: .continuous)
                            .strokeBorder(Slide.red.opacity(0.25), lineWidth: k * 1.6)
                    )
                } else {
                    VStack(alignment: .leading, spacing: k * 14) {
                        ForEach(entries, id: \.self) { entry in
                            HStack(alignment: .top, spacing: k * 14) {
                                Text(entry.subject)
                                    .font(.system(size: k * 22, weight: .bold))
                                    .foregroundStyle(Slide.blue)
                                    .padding(.horizontal, k * 12)
                                    .padding(.vertical, k * 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: k * 10, style: .continuous)
                                            .fill(Slide.blueSoft)
                                    )
                                    .fixedSize()
                                Text(entry.students)
                                    .font(.system(size: k * 34, weight: .bold))
                                    .foregroundStyle(Slide.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(k * 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - 通用零件

    private func panelHeader(symbol: String, title: String, badge: String?) -> some View {
        HStack(spacing: k * 14) {
            Image(systemName: symbol)
                .font(.system(size: k * 26, weight: .semibold))
                .foregroundStyle(Slide.blue)
                .frame(width: k * 52, height: k * 52)
                .background(
                    RoundedRectangle(cornerRadius: k * 16, style: .continuous).fill(Slide.blueSoft)
                )
            Text(title)
                .font(.system(size: k * 38, weight: .bold))
                .foregroundStyle(Slide.blue)
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.system(size: k * 22, weight: .semibold))
                    .foregroundStyle(Slide.gray)
                    .padding(.horizontal, k * 14)
                    .padding(.vertical, k * 7)
                    .background(Capsule().fill(Slide.blueSoft.opacity(0.7)))
            }
        }
    }

    private func emptyState(symbol: String, text: String) -> some View {
        HStack(spacing: k * 16) {
            Image(systemName: symbol)
                .font(.system(size: k * 34, weight: .regular))
            Text(text)
                .font(.system(size: k * 34, weight: .medium))
        }
        .foregroundStyle(Slide.gray)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - 字号自适应

    /// 内容区总高（作业卡与右列同高）
    var contentAvailable: CGFloat {
        Slide.h - Slide.margin * 2 - 132 - Slide.gap
            - (vm.announcements.isEmpty ? 0 : estimatedAnnouncementHeight + Slide.gap)
    }

    var estimatedAnnouncementHeight: CGFloat {
        let width = contentWidth - 26 * 2 - 62 - 20
        var height: CGFloat = 40
        for item in vm.announcements {
            height += CGFloat(TextMeasure.lines(item.text, size: 44 * 0.86, width: width)) * 56 + 10
        }
        return max(112, height)
    }
}

extension SlideView {
    /// 出图工具的调试信息（版式是否溢出/留白过多一目了然）
    static func debugReport(vm: ViewModel) -> String {
        let view = SlideView(vm: vm, showBadge: true, size: CGSize(width: Slide.w, height: Slide.h))
        let layout = view.homeworkLayout
        let heights = view.columnHeights(layout.size, columns: layout.columns)
        return [
            "contentAvailable=\(Int(view.contentAvailable))",
            "homeworkAvailable=\(Int(view.homeworkAvailable))",
            "announcementH=\(Int(view.estimatedAnnouncementHeight))",
            "fontSize=\(Int(layout.size))",
            "columns=\(layout.columns)",
            "contentHeight=\(Int(heights.max() ?? 0))",
            "spacing=\(Int(layout.spacing))",
            "scheduleH=\(Int(view.scheduleCardHeight))",
            "groups=\(view.groups.count)",
            "lines=\(view.groups.reduce(0) { $0 + $1.subjects.reduce(0) { $0 + $1.entries.count } })",
        ].joined(separator: " ")
    }
}

/// 文本测量：只用于「挑一个放得下的字号」，屏幕与导出都走同一份判断
enum TextMeasure {
    static func lines(_ text: String, size: CGFloat, width: CGFloat) -> Int {
        guard !text.isEmpty, width > 1 else { return 1 }
        let font = NSFont.systemFont(ofSize: size, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let lineHeight = (font.ascender - font.descender + font.leading) * 1.02
        return max(1, Int((rect.height / lineHeight).rounded(.up)))
    }
}

@MainActor
enum SlideRenderer {
    /// 与屏幕完全一致的 1920×1080 画面 → PNG（2 倍像素密度）
    static func png(vm: ViewModel, showBadge: Bool, showRestDayGreeting: Bool = true) -> Data? {
        let view = SlideView(
            vm: vm,
            showBadge: showBadge,
            size: CGSize(width: Slide.w, height: Slide.h),
            showRestDayGreeting: showRestDayGreeting
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(width: Slide.w, height: Slide.h)
        guard let cg = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: Slide.w, height: Slide.h)
        return rep.representation(using: .png, properties: [:])
    }
}
