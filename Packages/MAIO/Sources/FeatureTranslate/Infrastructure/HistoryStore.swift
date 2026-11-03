import Foundation
import MAIOKit
import Observation
import os

/// 翻译历史，保存在 data/translate/history.json。启动后第一次使用时读取，之后在内存中维护，写盘在后台进行。
@MainActor
@Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []
    @ObservationIgnored private let storage: any StorageService
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private var loaded = false
    /// 串行写盘：新的写入等上一次完成，保证文件里是最新内容
    @ObservationIgnored private var lastWrite: Task<Void, Never>?

    init(storage: any StorageService, logger: Logger) {
        self.storage = storage
        self.logger = logger
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        guard let url = try? fileURL(), let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            entries = try decoder.decode([HistoryEntry].self, from: data)
        } catch {
            logger.error("翻译历史读取失败，已忽略：\(error.localizedDescription)")
        }
    }

    func add(_ entry: HistoryEntry, limit: Int) {
        load()
        entries = HistoryList.adding(entry, to: entries, limit: limit)
        persist()
    }

    func remove(_ id: HistoryEntry.ID) {
        load()
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        entries = []
        loaded = true
        persist()
    }

    private func fileURL() throws -> URL {
        try storage.dataDirectory().appending(path: "history.json")
    }

    private func persist() {
        let snapshot = entries
        guard let url = try? fileURL() else { return }
        let logger = logger
        let previous = lastWrite
        lastWrite = Task.detached(priority: .utility) {
            await previous?.value
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            do {
                try encoder.encode(snapshot).write(to: url, options: .atomic)
            } catch {
                logger.error("翻译历史保存失败：\(error.localizedDescription)")
            }
        }
    }
}
