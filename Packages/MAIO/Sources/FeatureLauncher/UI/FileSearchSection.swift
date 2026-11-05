import AppKit
import MAIOUI
import SwiftUI

/// 设置页的"文件搜索"：开关、索引状态、完全磁盘访问权限、排除的目录、重建索引。
struct FileSearchSection: View {
    @Binding var value: LauncherSettings
    let status: FileIndexStatus?

    var body: some View {
        Section("文件搜索") {
            Toggle("全盘搜索文件和文件夹（像 Everything）", isOn: $value.fileSearchEnabled)
            if value.fileSearchEnabled {
                if let status {
                    LabeledContent("索引") {
                        HStack {
                            Text(status.summary).font(.caption).foregroundStyle(.secondary)
                            Button("重建索引") { status.rebuild?() }
                        }
                    }
                    if !status.fullDiskAccess {
                        accessWarning
                    }
                }
                LabeledContent("搜索语法") {
                    Text(
                        "空格 并且 · | 或 · ! 不要 · \"短语\" · *.pdf · ext:pdf;docx · type:picture · in:~/Documents · size:>100mb · dm:7d · regex:",
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                Stepper("“全部”里最多显示 \(value.maxFilesInAll) 个文件", value: $value.maxFilesInAll, in: 5 ... 100, step: 5)
                Toggle("索引 .app 等包的内部（条目会多一半左右）", isOn: $value.indexPackageContents)
                ExcludedPathsEditor(paths: $value.excludedPaths)
                Text("系统目录、其他磁盘、缓存和临时文件默认不索引。依赖目录（node_modules、.git……）、隐藏文件会索引，但排在后面。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var accessWarning: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("没有“完全磁盘访问”权限：桌面、文稿、下载和各个 App 的数据目录没有索引。")
                Text("在系统设置里给 MAIO 打开后，下次打开启动器会自动重新索引。").foregroundStyle(.secondary)
            }
            .font(.caption)
            Spacer()
            Button("打开系统设置") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

/// 额外排除的目录：列表 + 添加（选择文件夹）+ 删除
private struct ExcludedPathsEditor: View {
    @Binding var paths: [String]

    var body: some View {
        LabeledContent("不索引的目录") {
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(paths, id: \.self) { path in
                    HStack {
                        Text(path).font(.caption).lineLimit(1).truncationMode(.middle)
                        Button {
                            paths.removeAll { $0 == path }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("添加…") { choose() }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "不索引"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let path = url.path(percentEncoded: false).trimmingSuffix("/")
            if !paths.contains(path) {
                paths.append(path)
            }
        }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        count > 1 && hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
