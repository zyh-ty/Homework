import HomeworkKit
import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var pageSelection: Binding<Page?> {
        Binding(
            get: { state.page },
            set: { if let value = $0 { state.page = value } }
        )
    }

    private var modeSelection: Binding<Bool> {
        Binding(
            get: { state.submitOnly },
            set: { state.submitOnly = $0 }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: pageSelection) {
                Section("页面") {
                    ForEach(Page.allCases) { page in
                        Label(page.title, systemImage: page.symbol)
                            .tag(page)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 178, ideal: 190, max: 260)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(UI.canvas)
        }
        .navigationTitle(state.page.title)
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) { toastOverlay }
        .onAppear {
            state.openPresentWindow = { openWindow(id: "present") }
            state.closePresentWindow = { dismissWindow(id: "present") }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch state.page {
        case .edit:
            EditPage()
        case .week:
            WeekPage()
        case .settings:
            SettingsPage()
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 10))
                Text(state.dataDir.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(state.saveState == "已保存" ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(state.saveState)
                    .font(.system(size: 10))
            }
        }
        .foregroundStyle(UI.secondaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(state.dataDir.path)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if state.page == .edit {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    state.stepDay(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("上一天（←）")

                Menu {
                    ForEach(state.dayList, id: \.self) { day in
                        Button {
                            state.setDate(day, submitOnly: false)
                        } label: {
                            if day == state.viewDate {
                                Label(dayLabel(day), systemImage: "checkmark")
                            } else {
                                Text(dayLabel(day))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text(state.dayLabel)
                            .monospacedDigit()
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("选择日期")

                Button {
                    state.stepDay(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("下一天（→）")
            }

            ToolbarItem(placement: .principal) {
                Picker("显示", selection: modeSelection) {
                    Text("全部").tag(false)
                    Text("仅要交").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 176)
                .help("「仅要交」只显示上一上学日勾了“明天交”的作业")
            }
        } else {
            ToolbarItem(placement: .navigation) {
                Button {
                    state.page = .edit
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .help("返回编辑页（Esc）")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                state.goToday()
            } label: {
                Label("今天", systemImage: "location.fill")
            }
            .help("回到今天（⌘T）")

            Button {
                state.exportImage(manual: true, forToday: true)
            } label: {
                Label("出图", systemImage: "square.and.arrow.down")
            }
            .help("生成家庭作业图片（⌘D）")

            Button {
                state.startPresenting()
            } label: {
                Label("放映", systemImage: "play.fill")
            }
            .buttonStyle(.glassProminent)
            .help("全屏放映（F5）")
        }
    }

    private func dayLabel(_ day: String) -> String {
        "\(Schedule.dotDate(day))　\(Schedule.weekdayCN(day))"
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = state.toast {
            HStack(spacing: 8) {
                if let symbol = toast.symbol {
                    Image(systemName: symbol)
                }
                Text(toast.text)
                    .lineLimit(2)
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(UI.cardStroke, lineWidth: 0.8))
            .shadow(color: .black.opacity(0.16), radius: 14, y: 4)
            .padding(.bottom, 26)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
            .allowsHitTesting(false)
        }
    }
}
