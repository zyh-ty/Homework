import Foundation

/// 监听数据目录里 data.json 的变化。
/// 保存是「写 tmp + rename」的原子替换，换掉的是目录项而不是原文件内容，
/// 所以监听的是**目录**，事件来了再比对 data.json 的 inode / 大小 / 修改时间，
/// 自己写完调 acknowledge() 把基线刷新掉，避免把自己的保存当成外部改动。
public final class DataFileWatcher {
    public struct Stamp: Equatable {
        public var inode: UInt64
        public var size: Int
        public var modified: Date?

        public init(inode: UInt64, size: Int, modified: Date?) {
            self.inode = inode
            self.size = size
            self.modified = modified
        }
    }

    private let dir: URL
    private let file: URL
    private let handler: () -> Void
    private let handlerQueue: DispatchQueue
    private let queue = DispatchQueue(label: "local.zyh.homework.datawatch")

    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var stamp: Stamp?
    private let debounce: TimeInterval

    public init(
        dir: URL,
        debounce: TimeInterval = 0.6,
        handlerQueue: DispatchQueue = .main,
        handler: @escaping () -> Void
    ) {
        self.dir = dir
        self.file = Store.dataFile(dir)
        self.debounce = debounce
        self.handlerQueue = handlerQueue
        self.handler = handler
    }

    deinit {
        source?.cancel()
    }

    public func start() {
        stop()
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.scheduleCheck() }
        source.setCancelHandler { close(fd) }
        self.source = source
        stamp = currentStamp()
        source.resume()
    }

    public func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    public func restart() {
        start()
    }

    /// 自己刚写完文件：基线刷新，别把自己的保存当成外部改动
    public func acknowledge() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            self.pending = nil
            self.stamp = self.currentStamp()
        }
    }

    private func scheduleCheck() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let now = self.currentStamp()
            guard now != self.stamp else { return }
            self.stamp = now
            self.handlerQueue.async { self.handler() }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func currentStamp() -> Stamp? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path) else { return nil }
        return Stamp(
            inode: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            size: (attrs[.size] as? NSNumber)?.intValue ?? 0,
            modified: attrs[.modificationDate] as? Date
        )
    }
}
