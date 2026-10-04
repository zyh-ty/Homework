import Foundation
import Testing
@testable import HomeworkKit

private func snap(_ date: String, _ text: String) -> DataSnapshot {
    var data = AppData()
    var day = Day()
    day.homework = [HomeworkItem(subject: "语文", text: text)]
    data.days[date] = day
    return DataSnapshot(data: data, viewDate: date)
}

private func text(_ snapshot: DataSnapshot) -> String {
    snapshot.data.days[snapshot.viewDate]?.homework.first?.text ?? ""
}

@Test func undoRedoRoundTrip() {
    let history = UndoHistory()
    let s0 = snap("2026-10-01", "一")
    let s1 = snap("2026-10-01", "二")
    let base = Date()

    history.record(s0, name: "编辑作业", token: "field", at: base)
    #expect(history.canUndo)
    #expect(history.undoName == "编辑作业")

    let back = history.undo(current: s1, at: base.addingTimeInterval(1))
    #expect(text(back!.snapshot) == "一")
    #expect(!history.canUndo)
    #expect(history.canRedo)

    let forward = history.redo(current: back!.snapshot, at: base.addingTimeInterval(2))
    #expect(text(forward!.snapshot) == "二")
    #expect(history.canUndo)
    #expect(!history.canRedo)
}

@Test func undoOnEmptyStackReturnsNil() {
    let history = UndoHistory()
    #expect(history.undo(current: snap("2026-10-01", "一")) == nil)
    #expect(history.redo(current: snap("2026-10-01", "一")) == nil)
}

@Test func sameTokenWithinWindowCoalesces() {
    let history = UndoHistory(coalesceWindow: 2.5)
    let s0 = snap("2026-10-01", "一")
    let base = Date()

    history.record(s0, name: "编辑作业", token: "field:hw", at: base)
    history.record(snap("2026-10-01", "二"), name: "编辑作业", token: "field:hw", at: base.addingTimeInterval(0.4))
    history.record(snap("2026-10-01", "三"), name: "编辑作业", token: "field:hw", at: base.addingTimeInterval(0.8))

    #expect(history.undoStack.count == 1)
    let back = history.undo(current: snap("2026-10-01", "四"), at: base.addingTimeInterval(1))
    #expect(text(back!.snapshot) == "一")
}

@Test func windowExpiryStartsNewStep() {
    let history = UndoHistory(coalesceWindow: 2.5)
    let base = Date()

    history.record(snap("2026-10-01", "一"), name: "编辑作业", token: "field", at: base)
    history.record(snap("2026-10-01", "二"), name: "编辑作业", token: "field", at: base.addingTimeInterval(3.0))

    #expect(history.undoStack.count == 2)
    #expect(text(history.undo(current: snap("2026-10-01", "三"), at: base.addingTimeInterval(4))!.snapshot) == "二")
}

@Test func differentTokenDoesNotCoalesce() {
    let history = UndoHistory()
    let base = Date()

    history.record(snap("2026-10-01", "一"), name: "编辑作业", token: "homework#语文#0", at: base)
    history.record(snap("2026-10-01", "二"), name: "编辑作业", token: "homework#数学#0", at: base.addingTimeInterval(0.2))

    #expect(history.undoStack.count == 2)
}

@Test func newRecordClearsRedoStack() {
    let history = UndoHistory()
    let base = Date()

    history.record(snap("2026-10-01", "一"), name: "编辑作业", token: "a", at: base)
    _ = history.undo(current: snap("2026-10-01", "二"), at: base.addingTimeInterval(1))
    #expect(history.canRedo)

    history.record(snap("2026-10-01", "三"), name: "编辑公告", token: "b", at: base.addingTimeInterval(2))
    #expect(!history.canRedo)
}

@Test func undoBreaksCoalescing() {
    let history = UndoHistory()
    let base = Date()

    history.record(snap("2026-10-01", "一"), name: "编辑作业", token: "same", at: base)
    _ = history.undo(current: snap("2026-10-01", "二"), at: base.addingTimeInterval(0.3))
    history.record(snap("2026-10-01", "三"), name: "编辑作业", token: "same", at: base.addingTimeInterval(0.5))

    #expect(history.undoStack.count == 1)
    #expect(text(history.undo(current: snap("2026-10-01", "四"), at: base.addingTimeInterval(1))!.snapshot) == "三")
}

@Test func limitDropsOldestEntries() {
    let history = UndoHistory(limit: 3, coalesceWindow: 0)
    let base = Date()
    for index in 0..<6 {
        history.record(snap("2026-10-01", "\(index)"), name: "编辑作业", token: "t\(index)", at: base.addingTimeInterval(Double(index)))
    }
    #expect(history.undoStack.count == 3)
    #expect(text(history.undoStack.first!.snapshot) == "3")
}

@Test func clearEmptiesBothStacks() {
    let history = UndoHistory()
    history.record(snap("2026-10-01", "一"), name: "编辑作业", token: "a")
    _ = history.undo(current: snap("2026-10-01", "二"))
    history.clear()
    #expect(!history.canUndo)
    #expect(!history.canRedo)
}

@Test func snapshotKeepsViewDate() {
    let history = UndoHistory()
    history.record(snap("2026-09-30", "一"), name: "删除天数", token: "cmd:删除天数")
    let back = history.undo(current: snap("2026-10-01", "二"))
    #expect(back!.snapshot.viewDate == "2026-09-30")
}
