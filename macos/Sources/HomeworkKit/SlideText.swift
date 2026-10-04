import Foundation

/// 画面内容转文字版作业（发群里用）。样式与放映版式一致：同一学科多条作业才编号，
/// 「明天交」跟在各自条目后面，英语A / 英语B 在文字里不合并。
public enum SlideText {
    public enum Style: Hashable, Sendable {
        case title, section, subject, item, note
    }

    public struct Line: Hashable, Sendable {
        public var text: String
        public var style: Style

        public init(text: String, style: Style) {
            self.text = text
            self.style = style
        }
    }

    public static func lines(_ vm: ViewModel) -> [Line] {
        var out: [Line] = []
        var title = "\(Schedule.dotDate(vm.displayDate)) \(vm.weekday)"
        if vm.submitOnly { title += " · 只要交的" }
        out.append(Line(text: title, style: .title))

        var groups: [(subject: String, items: [HomeworkItem])] = []
        for item in vm.homework {
            let subject = item.subject
            if let index = groups.firstIndex(where: { $0.subject == subject }) {
                groups[index].items.append(item)
            } else {
                groups.append((subject, [item]))
            }
        }

        if !groups.isEmpty {
            out.append(Line(text: "【作业】", style: .section))
            for group in groups {
                if group.items.count == 1 {
                    let item = group.items[0]
                    out.append(Line(text: "\(group.subject)：\(item.text)\(tag(item))", style: .item))
                } else {
                    out.append(Line(text: "\(group.subject)：", style: .subject))
                    for (index, item) in group.items.enumerated() {
                        out.append(Line(text: "　\(index + 1). \(item.text)\(tag(item))", style: .item))
                    }
                }
            }
        }

        let speeches = vm.speeches.filter {
            !$0.students.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !speeches.isEmpty {
            out.append(Line(text: "【演讲提醒】", style: .section))
            for entry in speeches {
                out.append(Line(text: "\(entry.subject)：\(entry.students)", style: .item))
            }
        }

        if !vm.announcements.isEmpty {
            out.append(Line(text: "【公告】", style: .section))
            for item in vm.announcements {
                out.append(Line(text: "· \(item.text)", style: .item))
            }
        }

        if groups.isEmpty && speeches.isEmpty && vm.announcements.isEmpty {
            out.append(Line(text: vm.dayKind.greeting ?? "今天没有作业", style: .item))
        }
        return out
    }

    public static func plain(_ vm: ViewModel) -> String {
        lines(vm).map(\.text).joined(separator: "\n")
    }

    private static func tag(_ item: HomeworkItem) -> String {
        item.submitNext ? "（明天交）" : ""
    }
}
