import AppKit
import Foundation
import HomeworkKit

/// 无界面出图（用于验证放映版式）：
///   HomeworkMac --export out.png [--date 2026-09-30] [--mode all|submit] [--data <目录>]
enum SlideExport {
    static func isRequested(_ arguments: [String]) -> Bool {
        arguments.contains("--export")
    }

    static func run(arguments: [String]) {
        var out = "/tmp/slide.png"
        var date: String?
        var submitOnly = false
        var dataDir: URL?

        var index = 1
        while index < arguments.count {
            let arg = arguments[index]
            func next() -> String? {
                index + 1 < arguments.count ? arguments[index + 1] : nil
            }
            switch arg {
            case "--export":
                if let value = next() { out = value; index += 1 }
            case "--date":
                if let value = next() { date = value; index += 1 }
            case "--mode":
                if let value = next() { submitOnly = value == "submit"; index += 1 }
            case "--data":
                if let value = next() { dataDir = URL(fileURLWithPath: value); index += 1 }
            default:
                break
            }
            index += 1
        }

        let dir = dataDir ?? Store.resolveDataDir()
        let (data, _) = Store.loadOrRecover(dir)
        let target = date ?? Schedule.todayString()
        let holidays = HolidayService()
        let skipHoliday = UserDefaults.standard.object(forKey: "skipHolidayHomework") as? Bool ?? true
        let vm = Schedule.viewModel(data, date: target, submitOnly: submitOnly, holidays: holidays.table)
        guard let png = MainActor.assumeIsolated({
            SlideRenderer.png(vm: vm, showBadge: data.settings.showBadge, showRestDayGreeting: skipHoliday)
        }) else {
            FileHandle.standardError.write(Data("渲染失败\n".utf8))
            exit(2)
        }
        if arguments.contains("--debug") {
            print(MainActor.assumeIsolated { SlideView.debugReport(vm: vm) })
        }
        do {
            try png.write(to: URL(fileURLWithPath: out))
            print("已写出 \(out) · \(vm.displayDate) \(vm.weekday)\(submitOnly ? " · 仅要交" : "")")
        } catch {
            FileHandle.standardError.write(Data("写入失败：\(error)\n".utf8))
            exit(3)
        }
    }
}
