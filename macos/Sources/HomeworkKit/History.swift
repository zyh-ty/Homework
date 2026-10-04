import Foundation

/// 撤销/重做的状态快照：整份数据 + 当时选中的日期
public struct DataSnapshot {
    public var data: AppData
    public var viewDate: String

    public init(data: AppData, viewDate: String) {
        self.data = data
        self.viewDate = viewDate
    }
}

/// 快照式撤销栈：每次提交记一份「变更前」的快照；同一编辑点（token 相同）在时间窗内的
/// 连续提交合并成一步，避免打字时一个字符一步。
public final class UndoHistory {
    public struct Entry {
        public let snapshot: DataSnapshot
        public let name: String
        let token: String
        var at: Date
    }

    public var limit: Int
    public var coalesceWindow: TimeInterval
    public private(set) var undoStack: [Entry] = []
    public private(set) var redoStack: [Entry] = []

    private var lastToken: String?
    private var lastAt = Date.distantPast

    public init(limit: Int = 60, coalesceWindow: TimeInterval = 2.5) {
        self.limit = limit
        self.coalesceWindow = coalesceWindow
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoName: String? { undoStack.last?.name }
    public var redoName: String? { redoStack.last?.name }

    /// 记一份「变更前」的快照。token 相同且距上次提交不超过 coalesceWindow 时并入上一步。
    public func record(_ snapshot: DataSnapshot, name: String, token: String? = nil, at now: Date = Date()) {
        let key = token ?? name
        if !undoStack.isEmpty, lastToken == key, now.timeIntervalSince(lastAt) <= coalesceWindow {
            undoStack[undoStack.count - 1].at = now
            lastAt = now
            redoStack.removeAll()
            return
        }
        undoStack.append(Entry(snapshot: snapshot, name: name, token: key, at: now))
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
        lastToken = key
        lastAt = now
    }

    /// 撤销：弹出「变更前」快照，把当前状态压入重做栈
    @discardableResult
    public func undo(current: DataSnapshot, at now: Date = Date()) -> (snapshot: DataSnapshot, name: String)? {
        guard let entry = undoStack.popLast() else { return nil }
        redoStack.append(Entry(snapshot: current, name: entry.name, token: entry.token, at: now))
        breakCoalescing()
        return (entry.snapshot, entry.name)
    }

    @discardableResult
    public func redo(current: DataSnapshot, at now: Date = Date()) -> (snapshot: DataSnapshot, name: String)? {
        guard let entry = redoStack.popLast() else { return nil }
        undoStack.append(Entry(snapshot: current, name: entry.name, token: entry.token, at: now))
        breakCoalescing()
        return (entry.snapshot, entry.name)
    }

    /// 断开合并：切天、撤销/重做之后，下一次编辑必须开新的一步
    public func breakCoalescing() {
        lastToken = nil
        lastAt = .distantPast
    }

    public func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        breakCoalescing()
    }
}
