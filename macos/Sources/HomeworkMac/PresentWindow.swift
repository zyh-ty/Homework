import AppKit
import Combine
import HomeworkKit
import SwiftUI

struct PresentWindow: View {
    @Environment(AppState.self) private var state
    @State private var tick = 0
    @State private var hostWindow: NSWindow?
    @State private var requested = false
    @State private var retries = 0
    @State private var lastScreens: Set<UInt32> = []
    @State private var pendingScreen: NSScreen?

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Slide.w, geo.size.height / Slide.h)
            let size = CGSize(width: Slide.w * scale, height: Slide.h * scale)
            ZStack {
                Color.black
                SlideView(
                    vm: state.presentViewModel,
                    showBadge: state.data.settings.showBadge,
                    size: size
                )
                .clipShape(RoundedRectangle(cornerRadius: scale * 2, style: .continuous))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .background(Color.black)
        .onContinuousHover { phase in
            if case .active = phase { NSCursor.setHiddenUntilMouseMoves(true) }
        }
        .background(WindowAccessor(tick: tick) { window in
            adopt(window)
        })
        .onAppear {
            // 窗口会被系统复用，第二次打开时 makeNSView 不再调用：靠 tick 触发一次更新，
            // 再配合 didBecomeKey 兜底，保证每次打开都进全屏。
            state.isPresenting = true
            requested = false
            retries = 0
            pendingScreen = nil
            lastScreens = Set(NSScreen.screens.map(\.displayID))
            tick &+= 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if let hostWindow { requestFullScreen(hostWindow) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window = note.object as? NSWindow, window === hostWindow else { return }
            requestFullScreen(window)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            guard let window = note.object as? NSWindow, window === hostWindow else { return }
            guard let target = pendingScreen else { return }
            pendingScreen = nil
            window.setFrame(target.frame, display: true)
            requestFullScreen(window, reset: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screensChanged()
        }
        .contextMenu {
            Button(state.submitOnly ? "切换为显示全部" : "切换为仅要交") {
                state.submitOnly.toggle()
            }
            Button("生成作业图片") {
                state.exportImage(manual: true)
            }
            Button("复制作业图片") {
                state.copySlideImage()
            }
            Button("复制文字版作业") {
                state.copySlideText()
            }
            Button("分享…") {
                state.shareSlide()
            }
            Divider()
            Menu("放映屏幕") {
                Button(screenMenuTitle(nil)) { useScreen(nil) }
                Divider()
                ForEach(NSScreen.screens, id: \.displayID) { screen in
                    Button(screenMenuTitle(screen)) { useScreen(screen) }
                }
            }
            Divider()
            Button("退出放映") {
                state.stopPresenting()
            }
        }
        .onExitCommand { state.stopPresenting() }
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                ToastView(toast: toast, scale: 1.6)
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .onDisappear { state.stopPresenting() }
    }

    private func adopt(_ window: NSWindow) {
        hostWindow = window
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        NSCursor.setHiddenUntilMouseMoves(true)
        if let target = Presenter.shared.targetScreen {
            window.setFrame(target.frame, display: true)
        }
        requestFullScreen(window)
    }

    /// 进入全屏：窗口刚上屏时可能被系统忽略，失败就重试几次
    private func requestFullScreen(_ window: NSWindow, reset: Bool = false) {
        guard state.isPresenting else { return }
        if reset {
            requested = false
            retries = 0
        }
        if window.styleMask.contains(.fullScreen) {
            requested = true
            return
        }
        guard !requested || retries < 4 else { return }
        requested = true
        retries += 1
        window.toggleFullScreen(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak window] in
            guard let window, state.isPresenting, window.isVisible else { return }
            if !window.styleMask.contains(.fullScreen) {
                requestFullScreen(window)
            }
        }
    }

    // MARK: - 屏幕

    private func screenMenuTitle(_ screen: NSScreen?) -> String {
        guard let screen else {
            return Presenter.shared.screenID == 0 ? "自动（当前屏幕）✓" : "自动（当前屏幕）"
        }
        let picked = Presenter.shared.screenID == screen.displayID
        return picked ? "\(screen.localizedName) ✓" : screen.localizedName
    }

    private func useScreen(_ screen: NSScreen?) {
        Presenter.shared.screenID = screen?.displayID ?? 0
        guard let window = hostWindow else { return }
        if let screen {
            retarget(window, to: screen)
            state.show("放映屏幕：\(screen.localizedName)", symbol: "display")
        } else {
            state.show("放映屏幕：自动", symbol: "display")
        }
    }

    /// 投影热插拔：指定的屏优先；自动模式下新接入的屏直接跟过去，拔掉则退回主屏
    private func screensChanged() {
        let current = Set(NSScreen.screens.map(\.displayID))
        let added = current.subtracting(lastScreens)
        let removed = lastScreens.subtracting(current)
        lastScreens = current
        guard state.isPresenting, let window = hostWindow else { return }

        if Presenter.shared.forgetMissingScreen() {
            state.show("指定的放映屏幕已断开，改回自动", symbol: "display.trianglebadge.exclamationmark")
            fallback(window)
            return
        }
        if let target = Presenter.shared.targetScreen {
            retarget(window, to: target)
        } else if let id = added.first, let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
            retarget(window, to: screen)
            state.show("已把放映挪到 \(screen.localizedName)", symbol: "display")
        } else if !removed.isEmpty {
            fallback(window)
        }
    }

    private func fallback(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.screens.first else { return }
        if window.styleMask.contains(.fullScreen) {
            if window.frame.origin == screen.frame.origin { return }
            pendingScreen = screen
            window.toggleFullScreen(nil)
        } else {
            window.setFrame(screen.frame, display: true)
            requestFullScreen(window, reset: true)
        }
    }

    /// 挪到指定屏幕：全屏中要先退出原生全屏、换屏、再重新全屏
    private func retarget(_ window: NSWindow, to screen: NSScreen) {
        if window.styleMask.contains(.fullScreen) {
            if window.screen?.displayID == screen.displayID { return }
            pendingScreen = screen
            window.toggleFullScreen(nil)
        } else {
            if window.frame.origin != screen.frame.origin {
                window.setFrame(screen.frame, display: true)
            }
            requestFullScreen(window, reset: true)
        }
    }
}

/// 拿到承载视图的 NSWindow（make 与 update 都回调，窗口复用也能拿到）
struct WindowAccessor: NSViewRepresentable {
    var tick: Int = 0
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { onWindow(window) }
        }
    }
}
