import SwiftUI

/// 存储占用与手动清理：按类型 / 按月份的占用，删除最旧的 N MB，删除某日期之前的，清空。
struct StorageManagementView: View {
    let store: ClipStore
    @State private var stats: ClipStore.Stats?
    @State private var megabytes = 100
    @State private var cutoff = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var pending: Cleanup?
    @State private var message: String?

    enum Cleanup: Identifiable {
        case oldest(Int)
        case before(Date)
        case all

        var id: String {
            switch self {
            case let .oldest(size): "oldest-\(size)"
            case let .before(date): "before-\(date.timeIntervalSince1970)"
            case .all: "all"
            }
        }

        var title: String {
            switch self {
            case let .oldest(size): "删除最旧的 \(size) MB？"
            case let .before(date): "删除 \(date.formatted(date: .long, time: .omitted)) 之前的条目？"
            case .all: "清空全部历史？"
            }
        }
    }

    var body: some View {
        Group {
            LabeledContent("当前占用") {
                if let stats {
                    Text("\(ByteFormat.string(stats.total.bytes)) · \(stats.total.count) 条" + pinnedNote(stats))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            if let stats {
                breakdown(stats)
            }
            LabeledContent("删除最旧的") {
                // 分组表单里的 TextField 默认没有边框、基线也不和旁边的文字对齐，要显式指定
                HStack(alignment: .firstTextBaseline) {
                    TextField("", value: $megabytes, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("MB").foregroundStyle(.secondary)
                    Button("删除…") { pending = .oldest(max(1, megabytes)) }
                }
            }
            LabeledContent("删除此日期之前的") {
                HStack {
                    DatePicker("", selection: $cutoff, displayedComponents: .date).labelsHidden()
                    Button("删除…") { pending = .before(cutoff) }
                }
            }
            LabeledContent("清空") {
                Button("清空全部历史…", role: .destructive) { pending = .all }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await refresh() }
        .confirmationDialog(pending?.title ?? "", isPresented: isConfirming, presenting: pending) { cleanup in
            Button("删除", role: .destructive) { Task { await perform(cleanup) } }
        } message: { _ in
            Text("固定的条目不会被删除。此操作无法撤销。")
        }
    }

    private func breakdown(_ stats: ClipStore.Stats) -> some View {
        DisclosureGroup("占用明细") {
            ForEach(ClipKind.allCases, id: \.self) { kind in
                if let bucket = stats.byKind[kind] {
                    LabeledContent(kind.title, value: "\(ByteFormat.string(bucket.bytes)) · \(bucket.count) 条")
                }
            }
            Divider()
            ForEach(stats.byMonth.prefix(24), id: \.month) { entry in
                LabeledContent(entry.month, value: "\(ByteFormat.string(entry.bucket.bytes)) · \(entry.bucket.count) 条")
            }
        }
    }

    private func pinnedNote(_ stats: ClipStore.Stats) -> String {
        stats.pinned.count >= 1 ? "（其中固定 \(stats.pinned.count) 条）" : ""
    }

    private var isConfirming: SwiftUI.Binding<Bool> {
        SwiftUI.Binding(get: { pending != nil }, set: {
            if !$0 {
                pending = nil
            }
        })
    }

    private func perform(_ cleanup: Cleanup) async {
        do {
            let entries = try await store.retentionEntries()
            let ids = switch cleanup {
            case let .oldest(size): RetentionPolicy.oldest(entries, bytes: Int64(size) * 1_000_000)
            case let .before(date): RetentionPolicy.before(entries, date: date)
            case .all: entries.filter { !$0.isPinned }.map(\.id)
            }
            try await store.delete(ids)
            message = "已删除 \(ids.count) 条"
        } catch {
            message = error.localizedDescription
        }
        pending = nil
        await refresh()
    }

    private func refresh() async {
        stats = try? await store.stats()
    }
}
