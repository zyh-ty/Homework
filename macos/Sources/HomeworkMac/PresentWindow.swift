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
            tick &+= 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if let hostWindow { requestFullScreen(hostWindow) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window = note.object as? NSWindow, window === hostWindow else { return }
            requestFullScreen(window)
        }
        .contextMenu {
            Button(state.submitOnly ? "切换为显示全部" : "切换为仅要交") {
                state.submitOnly.toggle()
            }
            Button("生成作业图片") {
                state.exportImage(manual: true)
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
        .onDisappear { state.isPresenting = false }
    }

    private func adopt(_ window: NSWindow) {
        hostWindow = window
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        NSCursor.setHiddenUntilMouseMoves(true)
        requestFullScreen(window)
    }

    /// 进入全屏：窗口刚上屏时可能被系统忽略，失败就重试几次
    private func requestFullScreen(_ window: NSWindow) {
        guard state.isPresenting else { return }
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
