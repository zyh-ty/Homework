import Foundation

public let PERIODS = 9

/// 所有模型共用的键名（与 JSON 中的 snake_case 字段一一对应，编解码统一走 snake_case 策略）
enum JSONKey: String, CodingKey {
    case version
    case weeklySchedule
    case days
    case announcements
    case settings
    case dataDir
    case imageIntervalSecs
    case morningCutoff
    case showBadge
    case scheduleOverride
    case homework
    case speeches
    case copiedFromWeekday
    case subject
    case text
    case submitNext
    case students
    case id
    case done
}

/// 字段缺失 → 默认值（对齐 Rust 端容器级 `#[serde(default)]`）
/// 显式 null 或类型不符 → 抛出，整个文件加载失败并走备份恢复（对齐 Rust 端非 Option 字段的语义）
/// 注意必须用 `contains` 区分「字段不存在」与「字段存在但内容非法」：后者抛出的
/// keyNotFound 来自嵌套元素，不能被当成缺字段吞掉，否则会静默丢条目。
func decodeDefaulted<T: Decodable>(
    _ container: KeyedDecodingContainer<JSONKey>, _ key: JSONKey, _ fallback: T
) throws -> T {
    guard container.contains(key) else { return fallback }
    return try container.decode(T.self, forKey: key)
}

/// 真正可选的字段（对齐 Rust 端 `Option<T>`）：缺失或 null 都得到 nil，类型不符仍抛出
func decodeOptional<T: Decodable>(
    _ container: KeyedDecodingContainer<JSONKey>, _ key: JSONKey
) throws -> T? {
    try container.decodeIfPresent(T.self, forKey: key)
}

public struct HomeworkItem: Codable, Hashable, Sendable {
    public var subject: String
    public var text: String
    public var submitNext: Bool

    public init(subject: String, text: String, submitNext: Bool = false) {
        self.subject = subject
        self.text = text
        self.submitNext = submitNext
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: JSONKey.self)
        subject = try c.decode(String.self, forKey: .subject)
        text = try c.decode(String.self, forKey: .text)
        submitNext = try c.decode(Bool.self, forKey: .submitNext)
    }
}

public struct SpeechEntry: Codable, Hashable, Sendable {
    public var subject: String
    public var students: String

    public init(subject: String, students: String = "") {
        self.subject = subject
        self.students = students
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: JSONKey.self)
        subject = try c.decode(String.self, forKey: .subject)
        students = try c.decode(String.self, forKey: .students)
    }
}

public struct Day: Codable, Hashable, Sendable {
    public var scheduleOverride: [String?]
    public var homework: [HomeworkItem]
    public var speeches: [SpeechEntry]
    public var copiedFromWeekday: Int?

    public init(
        scheduleOverride: [String?] = Array(repeating: nil, count: PERIODS),
        homework: [HomeworkItem] = [],
        speeches: [SpeechEntry] = [],
        copiedFromWeekday: Int? = nil
    ) {
        self.scheduleOverride = scheduleOverride
        self.homework = homework
        self.speeches = speeches
        self.copiedFromWeekday = copiedFromWeekday
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: JSONKey.self)
        scheduleOverride = try decodeDefaulted(c, .scheduleOverride, Array(repeating: nil, count: PERIODS))
        homework = try decodeDefaulted(c, .homework, [])
        speeches = try decodeDefaulted(c, .speeches, [])
        copiedFromWeekday = try decodeOptional(c, .copiedFromWeekday)
        scheduleOverride = Schedule.normalizedOverride(scheduleOverride)
    }

    /// 显式写出 null（与原 Tauri 版数据文件保持一致，两边可互相读写）
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: JSONKey.self)
        try c.encode(scheduleOverride, forKey: .scheduleOverride)
        try c.encode(homework, forKey: .homework)
        try c.encode(speeches, forKey: .speeches)
        if let copiedFromWeekday {
            try c.encode(copiedFromWeekday, forKey: .copiedFromWeekday)
        } else {
            try c.encodeNil(forKey: .copiedFromWeekday)
        }
    }
}

public struct Announcement: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var text: String
    public var done: Bool

    public init(id: Int, text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: JSONKey.self)
        id = try c.decode(Int.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        done = try c.decode(Bool.self, forKey: .done)
    }
}

public struct Settings: Codable, Hashable, Sendable {
    public var dataDir: String?
    public var imageIntervalSecs: Int
    public var morningCutoff: String
    public var showBadge: Bool

    public init(
        dataDir: String? = nil,
        imageIntervalSecs: Int = 60,
        morningCutoff: String = "08:00",
        showBadge: Bool = true
    ) {
        self.dataDir = dataDir
        self.imageIntervalSecs = imageIntervalSecs
        self.morningCutoff = morningCutoff
        self.showBadge = showBadge
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: JSONKey.self)
        dataDir = try decodeOptional(c, .dataDir)
        imageIntervalSecs = try decodeDefaulted(c, .imageIntervalSecs, 60)
        morningCutoff = try decodeDefaulted(c, .morningCutoff, "08:00")
        showBadge = try decodeDefaulted(c, .showBadge, true)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: JSONKey.self)
        if let dataDir {
            try c.encode(dataDir, forKey: .dataDir)
        } else {
            try c.encodeNil(forKey: .dataDir)
        }
        try c.encode(imageIntervalSecs, forKey: .imageIntervalSecs)
        try c.encode(morningCutoff, forKey: .morningCutoff)
        try c.encode(showBadge, forKey: .showBadge)
    }
}

public struct AppData: Codable, Equatable, Sendable {
    public var version: Int
    public var weeklySchedule: [[String]]
    public var days: [String: Day]
    public var announcements: [Announcement]
    public var settings: Settings

    public init(
        version: Int = 1,
        weeklySchedule: [[String]] = Schedule.defaultWeeklySchedule(),
        days: [String: Day] = [:],
        announcements: [Announcement] = [],
        settings: Settings = Settings()
    ) {
        self.version = version
        self.weeklySchedule = weeklySchedule
        self.days = days
        self.announcements = announcements
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: JSONKey.self)
        version = try decodeDefaulted(c, .version, 1)
        weeklySchedule = try decodeDefaulted(c, .weeklySchedule, Schedule.defaultWeeklySchedule())
        days = try decodeDefaulted(c, .days, [:])
        announcements = try decodeDefaulted(c, .announcements, [])
        settings = try decodeDefaulted(c, .settings, Settings())
        normalize()
    }

    public mutating func normalize() {
        weeklySchedule = Schedule.normalizeWeekly(weeklySchedule)
        for (key, var day) in days {
            day.scheduleOverride = Schedule.normalizedOverride(day.scheduleOverride)
            days[key] = day
        }
    }

    public var nextAnnouncementID: Int {
        (announcements.map(\.id).max() ?? 0) + 1
    }
}

public struct Slot: Codable, Hashable, Sendable {
    public var name: String
    public var changed: Bool

    public init(name: String, changed: Bool = false) {
        self.name = name
        self.changed = changed
    }

    public var isEmpty: Bool { name.isEmpty }
}

public struct LaunchView: Hashable, Sendable {
    public var date: String
    public var submitOnly: Bool

    public init(date: String, submitOnly: Bool) {
        self.date = date
        self.submitOnly = submitOnly
    }
}

public struct ViewModel: Hashable, Sendable {
    public var date: String
    public var displayDate: String
    public var weekday: String
    public var submitOnly: Bool
    public var homeworkDate: String
    public var slots: [Slot]
    public var announcements: [Announcement]
    public var homework: [HomeworkItem]
    public var speeches: [SpeechEntry]
    public var speechWarn: Bool
    public var homeworkSuggestions: [String]
    public var speechSuggestions: [String]
    /// 画面这一天的性质（法定节假日 / 周末 / 调休上课日 / 正常上学）
    public var dayKind: DayKind

    public init(
        date: String,
        displayDate: String,
        weekday: String,
        submitOnly: Bool,
        homeworkDate: String,
        slots: [Slot],
        announcements: [Announcement],
        homework: [HomeworkItem],
        speeches: [SpeechEntry],
        speechWarn: Bool,
        homeworkSuggestions: [String],
        speechSuggestions: [String],
        dayKind: DayKind = .school
    ) {
        self.date = date
        self.displayDate = displayDate
        self.weekday = weekday
        self.submitOnly = submitOnly
        self.homeworkDate = homeworkDate
        self.slots = slots
        self.announcements = announcements
        self.homework = homework
        self.speeches = speeches
        self.speechWarn = speechWarn
        self.homeworkSuggestions = homeworkSuggestions
        self.speechSuggestions = speechSuggestions
        self.dayKind = dayKind
    }
}

public struct WeekOverview: Hashable, Sendable {
    public var dates: [String]
    public var rows: [[Slot]]

    public init(dates: [String], rows: [[Slot]]) {
        self.dates = dates
        self.rows = rows
    }
}

public let ALL_SUBJECTS = [
    "语文", "数学", "英语A", "英语B", "物理", "化学", "生物", "历史", "地理",
    "政治", "体育", "美术", "音乐", "信息", "心理", "劳技", "自习", "班会",
]
