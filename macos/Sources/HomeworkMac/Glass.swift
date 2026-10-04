import AppKit
import SwiftUI

/// 主窗口的液态玻璃外观（macOS 26）。
///
/// 玻璃要透到桌面，窗口本身必须是非不透明的：否则 `glassEffect` 只能透到窗口
/// 自己的底色，看上去就是一块淡淡的灰。这里把标题栏与整窗背景都交还给系统材质，
/// 再让内容层叠玻璃。放映窗口是独立的 Scene（纯黑底 + 幻灯片），不受这里影响。
enum GlassAppearance {
    /// 非不透明窗口：让系统材质与桌面透上来
    static func apply(to window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        // 让标题栏与工具栏也吃系统材质，避免顶部出现一条实底
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        // 拖动窗口时保持玻璃实时重算
        window.isMovableByWindowBackground = true
    }
}

/// 主体背景：液态玻璃 + 一层很薄的白色。
///
/// 侧边栏是 `NavigationSplitView` 自带的系统材质，比这里更"实"；
/// 主体刻意只垫一点点白，让它明显比侧边栏通透（改 `veil` 即可调深浅）。
/// 深色外观下垫黑，避免发灰。
struct GlassWindowBackground: View {
    /// 0 = 完全通透，1 = 纯实底
    var veil: Double = 0.22

    private var veilColor: Color {
        UI.dynamic(
            light: NSColor.white.withAlphaComponent(veil),
            dark: NSColor.black.withAlphaComponent(veil * 0.8)
        )
    }

    var body: some View {
        Color.clear
            .glassEffect(.regular, in: .rect(cornerRadius: 0))
            .overlay(veilColor)
            .ignoresSafeArea()
    }
}

/// 把主窗口调成玻璃外观（窗口复用也会重新应用）
struct WindowGlassConfigurator: ViewModifier {
    @State private var tick = 0

    func body(content: Content) -> some View {
        content
            .background(WindowAccessor(tick: tick) { window in
                GlassAppearance.apply(to: window)
            })
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                guard let window = note.object as? NSWindow else { return }
                GlassAppearance.apply(to: window)
            }
    }
}

extension View {
    func glassWindow() -> some View {
        modifier(WindowGlassConfigurator())
    }
}
