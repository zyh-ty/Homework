import HomeworkKit
import SwiftUI

struct WeekPage: View {
    @Environment(AppState.self) private var state
    @State private var editing = false
    @State private var rows: [[String]] = []

    private var monday: String { Schedule.mondayOf(state.viewDate) }
    private var overview: WeekOverview { Schedule.weekOverview(state.data, monday: monday) }

    var body: some View {
        VStack(spacing: 12) {
            header
            VStack(spacing: 10) {
                GeometryReader { geo in
                    let rowHeight = max(30, min(66, (geo.size.height - 46) / CGFloat(PERIODS) - 1))
                    Group {
                        if editing {
                            templateTable(rowHeight: rowHeight)
                        } else {
                            overviewTable(rowHeight: rowHeight)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
                if editing {
                    HStack {
                        Spacer()
                        Button("取消") { editing = false }
                        Button("保存模版") {
                            state.setWeeklySchedule(rows)
                            editing = false
                            state.show("周课表模版已更新", symbol: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    legend
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(UI.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(UI.cardStroke, lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(UI.accent)
            Text(editing ? "编辑周课表模版" : "本周总览")
                .font(.system(size: 14, weight: .semibold))
            Text(editing ? "每一列对应一周中的一天，回车可逐格录入" : "\(Schedule.dotDate(monday)) 起 · 调课显示为红色")
                .hintStyle()
            Spacer()
            Button(editing ? "预览本周" : "修改周课表模版") {
                if editing {
                    editing = false
                } else {
                    rows = state.data.weeklySchedule.map { row in
                        var copy = row
                        while copy.count < PERIODS { copy.append("") }
                        return copy
                    }
                    editing = true
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 4)
    }

    private var weekdays: [String] { ["周一", "周二", "周三", "周四", "周五", "周六", "周日"] }

    private func overviewTable(rowHeight: CGFloat) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                cell("", tint: UI.subtleFill.opacity(0.5), bold: true, height: rowHeight + 8)
                    .frame(width: 44)
                ForEach(Array(overview.dates.enumerated()), id: \.element) { index, date in
                    VStack(spacing: 1) {
                        Text(weekdays[index])
                            .font(.system(size: 12, weight: .semibold))
                        Text(date.suffix(5))
                            .font(.system(size: 10.5))
                            .monospacedDigit()
                            .foregroundStyle(date == state.today ? UI.accent : UI.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight + 8)
                    .background(date == state.today ? UI.accent.opacity(0.13) : UI.subtleFill.opacity(0.35))
                }
            }
            ForEach(0..<PERIODS, id: \.self) { period in
                GridRow {
                    Text("\(period + 1)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(UI.secondaryText)
                        .frame(width: 44)
                        .frame(height: rowHeight)
                        .background(UI.subtleFill.opacity(0.5))
                    ForEach(Array(overview.dates.enumerated()), id: \.element) { index, date in
                        let slot = overview.rows[index][period]
                        Text(slot.name)
                            .font(.system(size: 13, weight: slot.changed ? .bold : .regular))
                            .foregroundStyle(slot.changed ? Color.red : Color.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: rowHeight)
                            .background(date == state.today ? UI.accent.opacity(0.08) : Color.clear)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(UI.cardStroke, lineWidth: 0.8)
        )
    }

    private func templateTable(rowHeight: CGFloat) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                cell("", tint: UI.subtleFill.opacity(0.5), bold: true, height: rowHeight + 8)
                    .frame(width: 44)
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .background(UI.subtleFill.opacity(0.35))
                }
            }
            ForEach(0..<PERIODS, id: \.self) { period in
                GridRow {
                    Text("\(period + 1)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(UI.secondaryText)
                        .frame(width: 44)
                        .frame(height: rowHeight)
                        .background(UI.subtleFill.opacity(0.5))
                    ForEach(0..<7, id: \.self) { day in
                        TextField("", text: Binding(
                            get: {
                                guard day < rows.count, period < rows[day].count else { return "" }
                                return rows[day][period]
                            },
                            set: { value in
                                while rows.count <= day { rows.append(Array(repeating: "", count: PERIODS)) }
                                while rows[day].count <= period { rows[day].append("") }
                                rows[day][period] = value
                            }
                        ))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(UI.cardStroke, lineWidth: 0.8)
        )
    }

    private var legend: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.red.opacity(0.75))
                .frame(width: 10, height: 10)
            Text("红色 = 该日单独调课（在编辑页右侧课表卡里修改）")
                .hintStyle()
            Spacer()
            Text("今天整列高亮")
                .hintStyle()
        }
        .padding(.horizontal, 2)
    }

    private func cell(_ text: String, tint: Color, bold: Bool, height: CGFloat = 34) -> some View {
        Text(text)
            .font(.system(size: 11, weight: bold ? .semibold : .regular))
            .frame(height: height)
            .background(tint)
    }
}
