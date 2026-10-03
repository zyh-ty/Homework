import AppKit
import HomeworkKit
import SwiftUI

/// 放映画面（幻灯片）使用的固定浅色主题：屏幕与导出 PNG 完全一致
enum Slide {
    static let w: CGFloat = 1920
    static let h: CGFloat = 1080

    static let margin: CGFloat = 36
    static let gap: CGFloat = 22
    static let cardRadius: CGFloat = 30

    static let bgTop = Color(red: 0.973, green: 0.980, blue: 1.0)
    static let bgBottom = Color(red: 0.898, green: 0.933, blue: 0.980)

    static let bandTop = Color(red: 0.400, green: 0.612, blue: 0.878)
    static let bandBottom = Color(red: 0.169, green: 0.353, blue: 0.647)

    static let card = Color.white
    static let cardStroke = Color(red: 0.878, green: 0.906, blue: 0.953)

    static let text = Color(red: 0.106, green: 0.129, blue: 0.184)
    static let gray = Color(red: 0.541, green: 0.576, blue: 0.639)
    static let blue = Color(red: 0.180, green: 0.373, blue: 0.639)
    static let blueSoft = Color(red: 0.910, green: 0.941, blue: 0.984)
    static let blueLine = Color(red: 0.784, green: 0.855, blue: 0.949)

    static let amberTop = Color(red: 1.0, green: 0.878, blue: 0.663)
    static let amberBottom = Color(red: 0.961, green: 0.769, blue: 0.529)
    static let annText = Color(red: 0.451, green: 0.149, blue: 0.078)

    static let red = Color(red: 0.753, green: 0.153, blue: 0.176)
    static let redSoft = Color(red: 0.992, green: 0.922, blue: 0.925)
    static let orange = Color(red: 0.878, green: 0.482, blue: 0.0)
    static let orangeSoft = Color(red: 1.0, green: 0.953, blue: 0.886)

    static func dot(_ s: String) -> String { Schedule.dotDate(s) }
}

/// 应用界面（编辑/设置/总览）使用的自适应配色
enum UI {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.435, green: 0.663, blue: 0.949, alpha: 1)
            : NSColor(red: 0.180, green: 0.373, blue: 0.639, alpha: 1)
    })

    static let danger = Color(nsColor: .systemRed)
    static let warning = Color(nsColor: .systemOrange)

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardStroke = Color(nsColor: .separatorColor).opacity(0.7)
    static let subtleFill = Color(nsColor: .quaternaryLabelColor).opacity(0.35)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)

    static let canvas = dynamic(
        light: NSColor(red: 0.933, green: 0.949, blue: 0.976, alpha: 1),
        dark: NSColor(red: 0.106, green: 0.114, blue: 0.133, alpha: 1)
    )
}

extension View {
    /// 应用卡片：原生控件底色 + 细描边 + 柔和投影
    func appCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(UI.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(UI.cardStroke, lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    func cardTitleStyle() -> some View {
        self.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(UI.accent)
    }

    func hintStyle() -> some View {
        self.font(.system(size: 11))
            .foregroundStyle(UI.secondaryText)
    }
}

/// 键盘按键帽（设置页快捷键说明用）
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .frame(minWidth: 20)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(UI.subtleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(UI.cardStroke, lineWidth: 0.8)
            )
            .foregroundStyle(.primary)
    }
}

/// 卡片标题栏：图标 + 标题 + 右侧提示
struct CardHeader: View {
    let symbol: String
    let title: String
    var hint: String? = nil
    var tint: Color = UI.accent
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let trailing {
                trailing
            } else if let hint {
                Text(hint)
                    .hintStyle()
                    .lineLimit(1)
            }
        }
    }
}
