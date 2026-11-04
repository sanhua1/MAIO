import AppKit
import MAIOUI
import SwiftUI

/// 翻译窗口：顶部工具栏（固定、关闭）、原文输入、语言栏、各翻译源的结果卡片。
struct TranslateView: View {
    @Bindable var model: TranslateViewModel
    let width: Double
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            SourceEditor(model: model, inputFocused: $inputFocused)
            LanguageBar(model: model)
            results
        }
        .padding(12)
        .frame(width: width)
        .panelGlass(cornerRadius: 18)
        .onAppear { inputFocused = true }
        .onChange(of: model.focusToken) { _, _ in inputFocused = true }
        .onExitCommand { model.onClose?() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "character.bubble").foregroundStyle(.secondary)
            Text("翻译").font(.headline)
            Spacer()
            Button {
                model.isPinned.toggle()
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
            }
            .help(model.isPinned ? "取消固定（失去焦点时会自动关闭）" : "固定窗口（失去焦点时不关闭）")
            Button {
                model.onClose?()
            } label: {
                Image(systemName: "xmark")
            }
            .help("关闭（Esc）")
        }
        .buttonStyle(.borderless)
        // 拖动顶部这一栏移动窗口（左右各延伸到窗口边缘，上方包括内边距）
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .background(WindowDragArea())
        .padding(.horizontal, -12)
        .padding(.top, -12)
    }

    @ViewBuilder private var results: some View {
        if !model.cards.isEmpty {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.cards) { card in
                        ResultCardView(card: card, fontSize: model.fontSize, model: model)
                    }
                }
            }
            .frame(maxHeight: Self.maxResultsHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    static var maxResultsHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return max(240, screen * 0.6)
    }
}

/// 原文输入框：回车翻译，⇧回车换行。
private struct SourceEditor: View {
    @Bindable var model: TranslateViewModel
    var inputFocused: FocusState<Bool>.Binding

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.sourceText.isEmpty {
                Text("输入要翻译的文字，回车翻译，⇧回车换行")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
            }
            TextEditor(text: $model.sourceText)
                .font(.system(size: model.fontSize))
                .scrollContentBackground(.hidden)
                .focused(inputFocused)
                .frame(minHeight: 44, maxHeight: 160)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
                .onKeyPress(.return, phases: .down) { press in
                    guard !press.modifiers.contains(.shift) else { return .ignored }
                    model.translate()
                    return .handled
                }
        }
        .padding(4)
        .background(.background.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

/// 源语言 ⇄ 目标语言，以及"删除换行"按钮。
private struct LanguageBar: View {
    @Bindable var model: TranslateViewModel

    var body: some View {
        HStack(spacing: 6) {
            Picker("源语言", selection: $model.sourceLanguage) {
                ForEach(Language.allCases) { language in
                    Text(sourceTitle(language)).tag(language)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button("交换", systemImage: "arrow.left.arrow.right", action: model.swapLanguages)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("交换源语言和目标语言")
            Picker("目标语言", selection: targetBinding) {
                Text("自动（\(model.effectiveTarget.displayName)）").tag(Language?.none)
                ForEach(Language.targets) { language in
                    Text(language.displayName).tag(Language?.some(language))
                }
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button("删除换行", systemImage: "text.justify.left", action: model.removeLineBreaks)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("删除原文中的换行后重新翻译")
        }
        .controlSize(.small)
        .onChange(of: model.sourceLanguage) { _, _ in model.translate() }
    }

    private var targetBinding: SwiftUI.Binding<Language?> {
        SwiftUI.Binding(
            get: { model.targetOverride },
            set: { model.targetOverride = $0
                model.translate()
            },
        )
    }

    private func sourceTitle(_ language: Language) -> String {
        guard language == .auto, let detected = model.detected else { return language.displayName }
        return "自动（\(detected.displayName)）"
    }
}
