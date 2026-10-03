import AppKit
import HomeworkKit
import SwiftUI

struct HomeworkMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared

    var body: some Scene {
        WindowGroup("每日作业") {
            MainWindow()
                .environment(state)
        }
        .defaultSize(width: 1340, height: 880)
        .windowToolbarStyle(.unifiedCompact)
        .commands { appCommands }

        Window("放映", id: "present") {
            PresentWindow()
                .environment(state)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .appInfo) {
            Button("关于 每日作业") {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationName: "每日作业",
                    .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                    .credits: NSAttributedString(string: "原生 macOS 版 · 数据目录可在设置中更换"),
                ])
            }
        }
        CommandGroup(after: .sidebar) {
            Button("课表总览") { AppState.shared.page = .week }
                .keyboardShortcut("k", modifiers: .command)
            Button("设置") { AppState.shared.page = .settings }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu("每日作业") {
            Button("放映") { AppState.shared.startPresenting() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("退出放映") { AppState.shared.stopPresenting() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!AppState.shared.isPresenting)
            Divider()
            Button("今天") { AppState.shared.goToday() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(AppState.shared.isPresenting)
            Button("上一天") { AppState.shared.stepDay(-1) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(AppState.shared.isPresenting)
            Button("下一天") { AppState.shared.stepDay(1) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(AppState.shared.isPresenting)
            Divider()
            Button("生成作业图片") { AppState.shared.exportImage(manual: true, forToday: true) }
                .keyboardShortcut("d", modifiers: .command)
            Button("立即保存") { AppState.shared.saveNow(); AppState.shared.show("已保存", symbol: "checkmark.circle.fill") }
                .keyboardShortcut("s", modifiers: .command)
            Divider()
            Toggle("仅显示要交的作业", isOn: Binding(
                get: { AppState.shared.submitOnly },
                set: { AppState.shared.submitOnly = $0 }
            ))
            .keyboardShortcut("l", modifiers: .command)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.applyCurrent()
        NSApp.activate(ignoringOtherApps: true)
        KeyMonitor.install()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.saveNow()
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "跟随系统"
        }
    }

    static var current: AppAppearance {
        get { AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "light") ?? .light }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appearance")
            applyCurrent()
        }
    }

    static func applyCurrent() {
        switch current {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }
}

/// 全局键盘：F5 放映、Esc 退出、Alt+数字跳区、Alt+上下切条目、左右切天
enum KeyMonitor {
    static func install() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            AppState.shared.handleKey(event) ? nil : event
        }
    }
}
