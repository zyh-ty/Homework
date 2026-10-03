import AppKit
import EventKit
import Foundation
import HomeworkKit
import Observation

/// 读取系统日历里的「中国大陆节假日」（放假 + 调休上班），缓存到磁盘
@Observable
final class HolidayService {
    enum Status: Equatable {
        case idle
        case loading
        case ready
        case denied
        case failed(String)

        var text: String {
            switch self {
            case .idle: return "尚未读取"
            case .loading: return "正在读取日历…"
            case .ready: return "已连接系统日历"
            case .denied: return "未授权访问日历"
            case .failed(let message): return message
            }
        }
    }

    var status: Status = .idle
    var table: HolidayTable?
    private let store = EKEventStore()
    private var loading = false

    var calendarTitle: String? { table?.calendarTitle }
    var updatedAt: Date? { table?.updatedAt }
    var holidayCount: Int { table?.holidayDates.count ?? 0 }
    var workdayCount: Int { table?.workdayDates.count ?? 0 }

    private var cacheURL: URL {
        Store.appSupportDir.appendingPathComponent("holidays.json")
    }

    init() {
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(HolidayTable.self, from: data) {
            table = cached
            status = .ready
        }
    }

    /// 自动刷新：有缓存时后台静默更新，没有缓存时才弹授权
    func refreshIfNeeded() {
        if table == nil {
            refresh()
        } else {
            refresh(silently: true)
        }
    }

    func refresh(silently: Bool = false) {
        guard !loading else { return }
        if !silently { status = .loading }
        let authorization = EKEventStore.authorizationStatus(for: .event)
        switch authorization {
        case .fullAccess, .authorized:
            fetch()
        case .notDetermined:
            request()
        case .denied, .restricted:
            status = .denied
        default:
            request()
        }
    }

    private func request() {
        loading = true
        store.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                if granted {
                    self.fetch()
                } else {
                    self.status = .denied
                    if let error { self.status = .failed(error.localizedDescription) }
                }
            }
        }
    }

    private func fetch() {
        loading = true
        let store = self.store
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let calendars = store.calendars(for: .event).filter { calendar in
                let title = calendar.title
                return title.contains("节假日") || title.contains("假日") || title.lowercased().contains("holiday")
            }
            guard !calendars.isEmpty else {
                DispatchQueue.main.async {
                    self?.loading = false
                    self?.status = .failed("系统日历里没有「节假日」日历，可在日历 App 中订阅「中国大陆节假日」")
                }
                return
            }

            let calendar = Calendar(identifier: .gregorian)
            let now = Date()
            let start = calendar.date(byAdding: .day, value: -420, to: now) ?? now
            let end = calendar.date(byAdding: .day, value: 420, to: now) ?? now
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
            var entries: [String: HolidayEntry] = [:]

            for event in store.events(matching: predicate) {
                guard let title = event.title,
                      let parsed = HolidayRules.parse(title: title) else { continue }
                var day = event.startDate ?? now
                let last = event.endDate ?? day
                var guardCount = 0
                while day < last, guardCount < 90 {
                    guardCount += 1
                    let key = Schedule.format(day)
                    var entry = entries[key] ?? HolidayEntry(date: key, name: parsed.name, isHoliday: false, isWorkday: false)
                    entry.name = parsed.name
                    if parsed.isWorkday {
                        entry.isWorkday = true
                        entry.isHoliday = false
                    } else if !entry.isWorkday {
                        entry.isHoliday = true
                    }
                    entries[key] = entry
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }

            let table = HolidayTable(entries: entries, updatedAt: Date(), calendarTitle: calendars.first?.title)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                self.table = table
                self.persist(table)
                self.status = entries.isEmpty ? .failed("日历里没有找到节假日数据") : .ready
            }
        }
    }

    private func persist(_ table: HolidayTable) {
        try? FileManager.default.createDirectory(at: Store.appSupportDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(table) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func openCalendarApp() {
        if let url = URL(string: "ical://") {
            NSWorkspace.shared.open(url)
        }
    }
}
