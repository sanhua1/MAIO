import Foundation
import MAIOKit
import os

/// 读写 ~/Library/Application Support/MAIO 下的 JSON 文件。
/// 原则：配置损坏时备份坏文件并回落到默认值，绝不因此崩溃。
@MainActor
public final class ConfigStore {
    public let root: URL
    /// 启动以来遇到的配置问题（显示在设置页、HUD 中）
    public private(set) var issues: [String] = []
    private let logger = Logger(subsystem: "app.maio", category: "config")

    public init(root: URL) {
        self.root = root
    }

    /// 默认根目录：~/Library/Application Support/MAIO（可用环境变量 MAIO_HOME 覆盖，便于调试）。
    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["MAIO_HOME"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "MAIO", directoryHint: .isDirectory)
    }

    public func url(for relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    /// 读取 JSON。文件不存在返回 nil；文件损坏时备份并返回 nil。
    public func read(_ relativePath: String) -> JSONValue? {
        let url = url(for: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        } catch {
            quarantine(url, reason: "无法解析：\(error.localizedDescription)")
            return nil
        }
    }

    public func write(_ value: JSONValue, to relativePath: String) throws {
        let url = url(for: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    /// 读取并解码；缺失字段用 `defaultValue` 补齐；失败时备份坏文件并返回默认值。
    public func load<T: Codable>(_: T.Type, from relativePath: String, default defaultValue: T) -> T {
        guard let stored = read(relativePath) else { return defaultValue }
        do {
            let base = try JSONValue(encoding: defaultValue)
            return try stored.merged(over: base).decode(T.self)
        } catch {
            quarantine(url(for: relativePath), reason: "结构不匹配：\(error)")
            return defaultValue
        }
    }

    public func save(_ value: some Encodable, to relativePath: String) {
        do {
            try write(JSONValue(encoding: value), to: relativePath)
        } catch {
            report("保存 \(relativePath) 失败：\(error.localizedDescription)")
        }
    }

    func report(_ message: String) {
        logger.error("\(message, privacy: .public)")
        issues.append(message)
    }

    private func quarantine(_ url: URL, reason: String) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
        report("配置文件 \(url.lastPathComponent) \(reason)。已备份为 \(backup.lastPathComponent)，改用默认值。")
    }
}
