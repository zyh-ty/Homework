import AppKit
import Foundation

/// 放映期间的系统级行为：禁止休眠、锁定切换（隐藏 Dock/菜单栏、禁 ⌘Tab）、目标屏幕。
/// 这些偏机器本地，存 UserDefaults，不写进与 Windows 端共享的 data.json。
final class Presenter {
    static let shared = Presenter()

    private enum Key {
        static let keepAwake = "present.keepAwake"
        static let lockSwitching = "present.lockSwitching"
        static let screenID = "present.screenID"
    }

    private var activity: NSObjectProtocol?
    /// 是否正在放映（决定设置项改了要不要立刻生效）
    private(set) var isActive = false

    private init() {
        UserDefaults.standard.register(defaults: [
            Key.keepAwake: true,
            Key.lockSwitching: true,
            Key.screenID: 0,
        ])
    }

    /// 放映期间不熄屏、不待机
    var keepAwake: Bool {
        get { UserDefaults.standard.bool(forKey: Key.keepAwake) }
        set { UserDefaults.standard.set(newValue, forKey: Key.keepAwake) }
    }

    /// 放映期间隐藏 Dock 与菜单栏、禁用 ⌘Tab 切换（⌘⌥Esc 强制退出仍可用）
    var lockSwitching: Bool {
        get { UserDefaults.standard.bool(forKey: Key.lockSwitching) }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.lockSwitching)
            applyLock()
        }
    }

    /// 0 = 自动（就用放映窗口当前所在的屏幕）
    var screenID: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: Key.screenID)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: Key.screenID) }
    }

    /// 指定屏幕；自动模式下为 nil
    var targetScreen: NSScreen? {
        let id = screenID
        guard id != 0 else { return nil }
        return NSScreen.screens.first { $0.displayID == id }
    }

    /// 屏幕没了（投影拔掉）时自动退回
    func forgetMissingScreen() -> Bool {
        guard screenID != 0, targetScreen == nil else { return false }
        screenID = 0
        return true
    }

    func begin() {
        isActive = true
        startActivity()
        applyLock()
    }

    func end() {
        isActive = false
        stopActivity()
        NSApp.presentationOptions = []
    }

    /// 设置里改了开关后立即生效（不在放映中就什么都不做）
    func refresh() {
        if isActive && keepAwake {
            startActivity()
        } else {
            stopActivity()
        }
        applyLock()
    }

    func applyLock() {
        NSApp.presentationOptions = (isActive && lockSwitching)
            ? [.hideDock, .hideMenuBar, .disableProcessSwitching]
            : []
    }

    private func startActivity() {
        guard keepAwake, activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
            reason: "放映每日作业，避免中途黑屏"
        )
    }

    private func stopActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
