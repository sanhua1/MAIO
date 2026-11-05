import Foundation

/// 面板这边用的文件搜索：每次输入给搜索编个号，只采用最新一次的结果（打字快时，排队中的旧搜索直接跳过）。
@MainActor
final class FileSearchClient {
    let index: FileIndex
    private var token = 0
    private var task: Task<Void, Never>?
    private let home = NSHomeDirectory()

    init(index: FileIndex) {
        self.index = index
    }

    func search(_ text: String, foldersOnly: Bool, limit: Int, completion: @escaping @MainActor (FileResults) -> Void) {
        token += 1
        let current = token
        index.latestSearch.withLock { $0 = current }
        task?.cancel()
        guard let query = FileQuery(text, foldersOnly: foldersOnly) else {
            completion(FileResults(query: text))
            return
        }
        let index = index
        let home = home
        task = Task {
            guard let found = await index.search(query, limit: limit, token: current), !Task.isCancelled else { return }
            let items = found.hits.map {
                LauncherItem.file(path: $0.path, name: $0.name, isDirectory: $0.isDirectory, home: home)
            }
            completion(FileResults(query: text, items: items, total: found.total))
        }
    }

    func cancel() {
        task?.cancel()
        token += 1
        let current = token
        index.latestSearch.withLock { $0 = current }
    }
}
