import AppKit
import SwiftUI

/// 翻译历史：搜索、复制、删除、清空。
struct HistoryView: View {
    let store: HistoryStore
    @State private var query = ""
    @State private var confirmsClear = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜索原文或译文", text: $query).textFieldStyle(.roundedBorder)
                Button("清空…", role: .destructive) { confirmsClear = true }
                    .disabled(store.entries.isEmpty)
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            if filtered.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "还没有翻译历史" : "没有找到",
                    systemImage: "clock.arrow.circlepath",
                )
                .frame(maxHeight: .infinity)
            } else {
                List(filtered) { entry in
                    HistoryRow(entry: entry) { store.remove(entry.id) }
                }
            }
        }
        .frame(width: 620, height: 520)
        .onAppear { store.load() }
        .confirmationDialog("清空全部翻译历史？", isPresented: $confirmsClear) {
            Button("清空", role: .destructive) { store.clear() }
        }
    }

    private var filtered: [HistoryEntry] {
        store.entries.filter { $0.matches(query) }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.text).font(.body.weight(.medium)).lineLimit(3).textSelection(.enabled)
                Spacer()
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(entry.results, id: \.self) { item in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.service).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text(item.text).font(.callout).textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("复制原文") { copy(entry.text) }
            ForEach(entry.results, id: \.self) { item in
                Button("复制「\(item.service)」的译文") { copy(item.text) }
            }
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
