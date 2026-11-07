import Foundation

/// 文件索引的开关：按设置启动、停止、换扫描设置；打开面板时检查完全磁盘访问权限有没有变（变了就重扫）。
@MainActor
final class FileIndexController {
    let status = FileIndexStatus()
    private let file: URL
    private let model: LauncherViewModel
    private var index: FileIndex?
    private var options: ScanOptions?
    private var settings = LauncherSettings.defaultValue

    init(dataDirectory: URL, model: LauncherViewModel) {
        file = dataDirectory.appending(path: "index.bin")
        self.model = model
        status.rebuild = { [weak self] in self?.rebuild() }
    }

    func apply(_ newSettings: LauncherSettings) {
        settings = newSettings
        guard newSettings.fileSearchEnabled else {
            stop()
            return
        }
        let fresh = currentOptions()
        if let index {
            if fresh != options {
                options = fresh
                Task { await index.update(options: fresh) }
            }
        } else {
            start(fresh)
        }
    }

    /// 打开面板时调用：用户刚在系统设置里给了（或撤销了）完全磁盘访问权限，就按新范围重扫
    func checkAccess() {
        guard index != nil, IndexConfiguration.hasFullDiskAccess() != status.fullDiskAccess else { return }
        apply(settings)
    }

    func rebuild() {
        guard let index else { return }
        Task { await index.rebuild() }
    }

    func stop() {
        guard let index else { return }
        Task { await index.stop() }
        self.index = nil
        options = nil
        model.files = nil
        status.state = .idle
        model.fileState = .idle
    }

    private func start(_ fresh: ScanOptions) {
        let status = status
        let model = model
        let index = FileIndex(file: file, options: fresh) { state in
            Task { @MainActor in
                status.state = state
                model.fileState = state
            }
        }
        self.index = index
        options = fresh
        model.files = FileSearchClient(index: index)
        Task { await index.start() }
    }

    private func currentOptions() -> ScanOptions {
        let access = IndexConfiguration.hasFullDiskAccess()
        status.fullDiskAccess = access
        return IndexConfiguration.options(
            extraExcluded: settings.excludedPaths, indexPackageContents: settings.indexPackageContents, fullDiskAccess: access,
            indexTempFolder: settings.indexTempFolder,
        )
    }
}
