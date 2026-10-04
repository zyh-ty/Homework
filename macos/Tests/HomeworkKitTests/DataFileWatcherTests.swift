import Foundation
import Testing
@testable import HomeworkKit

// MARK: - 早晨分界线

@Test func nextCutoffIsTodayBeforeBoundary() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let morning = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 7, minute: 30))!
    let next = Schedule.nextCutoff(after: morning, cutoff: "08:00")
    let parts = cal.dateComponents([.day, .hour, .minute], from: next)
    #expect(parts.day == 1)
    #expect(parts.hour == 8)
    #expect(parts.minute == 0)
}

@Test func nextCutoffRollsToTomorrowAfterBoundary() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let noon = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12, minute: 5))!
    let next = Schedule.nextCutoff(after: noon, cutoff: "08:00")
    let parts = cal.dateComponents([.day, .hour], from: next)
    #expect(parts.day == 2)
    #expect(parts.hour == 8)
}

@Test func nextCutoffFallsBackToEightOnGarbage() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let seven = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 7, minute: 0))!
    let next = Schedule.nextCutoff(after: seven, cutoff: "不是时间")
    #expect(cal.component(.hour, from: next) == 8)
}

// MARK: - 数据文件外部改动

private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("homework-watch-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeJSON(_ dir: URL, _ text: String) {
    try? text.write(to: Store.dataFile(dir), atomically: true, encoding: .utf8)
}

@Test func watcherFiresOnExternalWrite() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    writeJSON(dir, "{\"version\":1}")

    let fired = DispatchSemaphore(value: 0)
    let queue = DispatchQueue(label: "test.watcher")
    let watcher = DataFileWatcher(dir: dir, debounce: 0.1, handlerQueue: queue) {
        fired.signal()
    }
    watcher.start()
    defer { watcher.stop() }

    writeJSON(dir, "{\"version\":1,\"extra\":true}")
    #expect(fired.wait(timeout: .now() + 5) == .success)
}

@Test func watcherIgnoresAcknowledgedWrites() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    writeJSON(dir, "{\"version\":1}")

    let fired = DispatchSemaphore(value: 0)
    let queue = DispatchQueue(label: "test.watcher.self")
    let watcher = DataFileWatcher(dir: dir, debounce: 0.1, handlerQueue: queue) {
        fired.signal()
    }
    watcher.start()
    defer { watcher.stop() }

    writeJSON(dir, "{\"version\":2}")
    watcher.acknowledge()
    Thread.sleep(forTimeInterval: 0.6)
    #expect(fired.wait(timeout: .now() + 0.5) == .timedOut)
}

@Test func watcherIgnoresUnrelatedDirectoryWrites() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    writeJSON(dir, "{\"version\":1}")

    let fired = DispatchSemaphore(value: 0)
    let queue = DispatchQueue(label: "test.watcher.other")
    let watcher = DataFileWatcher(dir: dir, debounce: 0.1, handlerQueue: queue) {
        fired.signal()
    }
    watcher.start()
    defer { watcher.stop() }

    try? "x".write(to: dir.appendingPathComponent("家庭作业_2026-10-01.png"), atomically: true, encoding: .utf8)
    #expect(fired.wait(timeout: .now() + 1.5) == .timedOut)
}

// MARK: - 保存与外部改动的一致性

@Test func saveUpdatesMainFileAndKeepsBackup() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    var data = AppData()
    data.days["2026-10-01"] = Day()
    try? Store.save(dir, data)
    #expect(FileManager.default.fileExists(atPath: Store.dataFile(dir).path))

    var second = data
    second.announcements = [Announcement(id: 1, text: "外部删除前")]
    try? Store.save(dir, second)
    let loaded = try? Store.load(dir)
    #expect(loaded?.announcements.count == 1)
    #expect(Store.listBackups(dir).count >= 1)
}
