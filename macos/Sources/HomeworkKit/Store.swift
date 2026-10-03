import Foundation

public struct StoreError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum Store {
    public static let configName = "每日作业配置.ini"
    public static let dataFileName = "data.json"
    public static let maxBackups = 30
    public static let imagePrefix = "家庭作业_"

    // MARK: - 路径

    /// 测试用：把配置目录指到临时目录，避免污染真实配置
    public static var configRootOverride: URL?

    public static var appSupportDir: URL {
        if let configRootOverride { return configRootOverride }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("每日作业", isDirectory: true)
    }

    public static var configFile: URL {
        appSupportDir.appendingPathComponent(configName)
    }

    public static var defaultDataDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return docs.appendingPathComponent("每日作业数据", isDirectory: true)
    }

    /// 数据目录：配置文件里的 data_dir 指针优先，否则 ~/Documents/每日作业数据
    public static func resolveDataDir() -> URL {
        if let text = try? String(contentsOf: configFile, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("data_dir=") else { continue }
                let value = String(trimmed.dropFirst("data_dir=".count)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
                }
            }
        }
        return defaultDataDir
    }

    public static func writeConfig(_ dir: URL) throws {
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        let text = "data_dir=\(dir.path)\n"
        do {
            try text.write(to: configFile, atomically: true, encoding: .utf8)
        } catch {
            throw StoreError("写入配置失败：\(error.localizedDescription)")
        }
    }

    public static func dataFile(_ dir: URL) -> URL {
        dir.appendingPathComponent(dataFileName)
    }

    public static func backupsDir(_ dir: URL) -> URL {
        dir.appendingPathComponent("backups", isDirectory: true)
    }

    public static func ensureDir(_ dir: URL) throws {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw StoreError("创建目录失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 编解码

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    public static func encode(_ data: AppData) throws -> Data {
        do {
            return try makeEncoder().encode(data)
        } catch {
            throw StoreError("序列化数据失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 读写

    public static func load(_ dir: URL) throws -> AppData {
        let path = dataFile(dir)
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw StoreError("读取 \(path.path) 失败：\(error.localizedDescription)")
        }
        do {
            var decoded = try makeDecoder().decode(AppData.self, from: data)
            decoded.normalize()
            return decoded
        } catch {
            throw StoreError("解析 \(path.path) 失败：\(error.localizedDescription)")
        }
    }

    /// 加载，失败时按备份新到旧恢复，成功则回写主文件；返回 (数据, 提示)
    public static func loadOrRecover(_ dir: URL) -> (AppData, String?) {
        do {
            return (try load(dir), nil)
        } catch {
            let reason = error.localizedDescription
            let candidates = listBackups(dir).sorted { $0.lastPathComponent > $1.lastPathComponent }
            for backup in candidates {
                guard let raw = try? Data(contentsOf: backup) else { continue }
                if var decoded = try? makeDecoder().decode(AppData.self, from: raw) {
                    decoded.normalize()
                    try? FileManager.default.removeItem(at: dataFile(dir))
                    try? FileManager.default.copyItem(at: backup, to: dataFile(dir))
                    return (decoded, "主数据损坏（\(reason)），已从备份 \(backup.lastPathComponent) 恢复")
                }
            }
            return (AppData(), "数据文件不可用（\(reason)），已创建空数据")
        }
    }

    /// 原子保存：先备份旧文件，写 tmp + fsync + 替换；然后修剪备份
    public static func save(_ dir: URL, _ data: AppData) throws {
        try ensureDir(dir)
        try ensureDir(backupsDir(dir))
        let target = dataFile(dir)
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) {
            let stamp = DateFmt.stamp.string(from: Date())
            let backup = backupsDir(dir).appendingPathComponent("data_\(stamp).json")
            try? fm.removeItem(at: backup)
            do {
                try fm.copyItem(at: target, to: backup)
            } catch {
                throw StoreError("备份失败：\(error.localizedDescription)")
            }
        }
        let tmp = dir.appendingPathComponent("data.json.tmp")
        let json = try encode(data)
        do {
            try? fm.removeItem(at: tmp)
            fm.createFile(atPath: tmp.path, contents: nil)
            let handle = try FileHandle(forWritingTo: tmp)
            try handle.write(contentsOf: json)
            try handle.synchronize()
            try handle.close()
        } catch {
            throw StoreError("写入临时文件失败：\(error.localizedDescription)")
        }
        do {
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: target)
            }
        } catch {
            throw StoreError("替换数据文件失败：\(error.localizedDescription)")
        }
        pruneBackups(dir)
    }

    public static func listBackups(_ dir: URL) -> [URL] {
        let bd = backupsDir(dir)
        guard let items = try? FileManager.default.contentsOfDirectory(at: bd, includingPropertiesForKeys: nil) else {
            return []
        }
        return items.filter { $0.pathExtension == "json" }
    }

    /// 保留最近 30 份，且同一天只留最新
    static func dayKey(of fileName: String) -> String {
        guard fileName.hasPrefix("data_"), fileName.count >= 13 else { return fileName }
        return String(fileName.dropFirst(5).prefix(8))
    }

    public static func pruneBackups(_ dir: URL) {
        let files = listBackups(dir).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var latestPerDay: [String: URL] = [:]
        for f in files {
            latestPerDay[dayKey(of: f.lastPathComponent)] = f
        }
        var survivors = Array(latestPerDay.values).sorted { $0.lastPathComponent < $1.lastPathComponent }
        while survivors.count > maxBackups {
            survivors.removeFirst()
        }
        let keep = Set(survivors.map(\.lastPathComponent))
        for f in files where !keep.contains(f.lastPathComponent) {
            try? FileManager.default.removeItem(at: f)
        }
    }

    public static func copyRecursive(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try ensureDir(dst)
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.isDirectoryKey])
        } catch {
            throw StoreError("读取源目录失败：\(error.localizedDescription)")
        }
        for item in items {
            let to = dst.appendingPathComponent(item.lastPathComponent)
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                try copyRecursive(from: item, to: to)
            } else {
                try? fm.removeItem(at: to)
                do {
                    try fm.copyItem(at: item, to: to)
                } catch {
                    throw StoreError("复制 \(item.lastPathComponent) 失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 迁移数据目录：复制 → 校验可加载 → 写配置；旧目录保留
    @discardableResult
    public static func migrate(from current: URL, to newDir: URL) throws -> URL {
        if current.standardizedFileURL == newDir.standardizedFileURL {
            throw StoreError("新目录与当前目录相同")
        }
        try copyRecursive(from: current, to: newDir)
        _ = try load(newDir)
        try writeConfig(newDir)
        return newDir
    }

    // MARK: - 出图

    /// 写出「家庭作业_今天.png」到数据目录，并清理其他日期的图片
    @discardableResult
    public static func exportImage(_ png: Data, dir: URL, date: String) throws -> URL {
        try ensureDir(dir)
        let name = "\(imagePrefix)\(date).png"
        let path = dir.appendingPathComponent(name)
        do {
            try png.write(to: path, options: .atomic)
        } catch {
            throw StoreError("写入图片失败：\(error.localizedDescription)")
        }
        if let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in items {
                let n = item.lastPathComponent
                if n.hasPrefix(imagePrefix), n.hasSuffix(".png"), n != name {
                    try? FileManager.default.removeItem(at: item)
                }
            }
        }
        return path
    }
}
