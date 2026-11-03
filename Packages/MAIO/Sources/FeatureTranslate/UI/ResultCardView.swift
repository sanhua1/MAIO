import AppKit
import SwiftUI

/// 单个翻译源的结果：标题栏（图标、名称、状态、复制、折叠），译文可选中复制，查单词时显示音标和释义。
struct ResultCardView: View {
    let card: TranslateViewModel.Card
    let fontSize: Double
    let model: TranslateViewModel
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleBar
            if !card.isCollapsed {
                content
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.35), in: .rect(cornerRadius: 10))
    }

    private var titleBar: some View {
        HStack(spacing: 6) {
            Image(systemName: card.symbol).foregroundStyle(.secondary)
            Text(card.name).font(.callout.weight(.medium))
            if isWorking {
                ProgressView().controlSize(.mini)
            }
            Spacer()
            if let text = card.text, !text.isEmpty {
                Button {
                    copy(text)
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .help("复制译文")
            }
            if case .failed = card.phase {
                Button("重试", systemImage: "arrow.clockwise") { model.retry(card.id) }
                    .labelStyle(.iconOnly)
                    .help("重试")
            }
            Button {
                model.toggleCollapsed(card.id)
            } label: {
                Image(systemName: card.isCollapsed ? "chevron.down" : "chevron.up")
            }
            .help(card.isCollapsed ? "展开" : "折叠")
        }
        .buttonStyle(.borderless)
        .contentShape(.rect)
        .onTapGesture(count: 2) { model.toggleCollapsed(card.id) }
    }

    @ViewBuilder private var content: some View {
        switch card.phase {
        case .loading:
            EmptyView()
        case let .streaming(text):
            translation(text)
        case let .done(result):
            if let dictionary = result.dictionary, !dictionary.isEmpty {
                DictionaryView(entry: dictionary, fontSize: fontSize)
            }
            translation(result.text)
        case let .failed(message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func translation(_ text: String) -> some View {
        Text(text)
            .font(.system(size: fontSize))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var isWorking: Bool {
        switch card.phase {
        case .loading, .streaming: true
        default: false
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

/// 词典模式：音标 + 按词性分组的释义。
private struct DictionaryView: View {
    let entry: DictionaryEntry
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !entry.phonetics.isEmpty {
                Text(entry.phonetics.joined(separator: "  "))
                    .font(.system(size: fontSize - 1))
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.meanings, id: \.self) { meaning in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(meaning.partOfSpeech)
                        .font(.system(size: fontSize - 2).italic())
                        .foregroundStyle(.secondary)
                    Text(meaning.terms.joined(separator: "；"))
                        .font(.system(size: fontSize))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider().padding(.vertical, 2)
        }
    }
}
