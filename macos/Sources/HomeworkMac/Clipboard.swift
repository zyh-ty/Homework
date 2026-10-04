import AppKit
import HomeworkKit

/// 剪贴板：图片按 PNG + TIFF 两种类型写入，文字带纯文本与 RTF
enum Clipboard {
    static func copy(png: Data) {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let image = NSImage(data: png), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([item])
    }

    static func copy(text: String, rich: NSAttributedString) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        let range = NSRange(location: 0, length: rich.length)
        if let rtf = rich.rtf(from: range, documentAttributes: [:]) {
            item.setData(rtf, forType: .rtf)
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([item])
    }
}

/// 分享面板（AirDrop / 信息 / 邮件…）：从鼠标位置弹出
enum Sharing {
    private static var picker: NSSharingServicePicker?

    static func present(_ items: [Any]) {
        guard let view = NSApp.keyWindow?.contentView else { return }
        let screenPoint = NSEvent.mouseLocation
        let inWindow = view.window?.convertPoint(fromScreen: screenPoint) ?? .zero
        let point = view.convert(inWindow, from: nil)
        let anchor = NSRect(x: point.x, y: point.y, width: 1, height: 1)
        let service = NSSharingServicePicker(items: items)
        picker = service
        service.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }
}

/// 文字版作业的富文本样式
enum SlideRichText {
    static func attributed(_ vm: ViewModel) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for line in SlideText.lines(vm) {
            out.append(NSAttributedString(string: line.text + "\n", attributes: attributes(for: line.style)))
        }
        return out
    }

    private static func attributes(for style: SlideText.Style) -> [NSAttributedString.Key: Any] {
        switch style {
        case .title:
            return [.font: NSFont.boldSystemFont(ofSize: 15)]
        case .section:
            return [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        case .subject:
            return [.font: NSFont.boldSystemFont(ofSize: 13)]
        case .item:
            return [.font: NSFont.systemFont(ofSize: 13)]
        case .note:
            return [.font: NSFont.systemFont(ofSize: 4)]
        }
    }
}
