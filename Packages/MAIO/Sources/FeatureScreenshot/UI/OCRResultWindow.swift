import AppKit
import MAIOKit
import MAIOUI
import SwiftUI

/// OCR 结果窗口的状态（spec 4.5）
@MainActor @Observable
final class OCRResultModel {
    var text: String
    @ObservationIgnored var translate: (String) -> Void = { _ in }
    @ObservationIgnored var copied: () -> Void = {}

    init(text: String) {
        self.text = text
    }

    func copy() {
        ImageExporter.copyToPasteboard(text: text)
        copied()
    }

    func removeLineBreaks() {
        text = TextCleaner.removingLineBreaks(text)
    }
}

/// 可编辑的识别结果，带"复制""删除换行""翻译"
struct OCRResultView: View {
    @Bindable var model: OCRResultModel

    var body: some View {
        VStack(spacing: 8) {
            TextEditor(text: $model.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background, in: .rect(cornerRadius: 8))
            HStack {
                Text("\(model.text.count) 个字符")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("删除换行", systemImage: "text.justify.left") { model.removeLineBreaks() }
                Button("翻译", systemImage: "translate") { model.translate(model.text) }
                Button("复制", systemImage: "doc.on.doc") { model.copy() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .frame(minWidth: 360, minHeight: 200)
    }
}

/// 每次识别打开一个结果窗口（可以同时开几个对照），放在屏幕正中间
@MainActor
final class OCRResultWindows: NSObject, NSWindowDelegate {
    private var windows: [NSWindow] = []

    func show(_ model: OCRResultModel) {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.size(for: model.text)),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false,
        )
        window.title = "识别结果"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: OCRResultView(model: model))
        place(window)
        windows.append(window)
        window.delegate = self
        AppActivation.activateForcibly()
        window.makeKeyAndOrderFront(nil)
    }

    func closeAll() {
        for window in windows {
            window.close()
        }
        windows.removeAll()
    }

    func windowWillClose(_ notification: Notification) {
        windows.removeAll { $0 === notification.object as? NSWindow }
    }

    /// 按文字多少估一个初始大小
    private static func size(for text: String) -> CGSize {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let longest = lines.map(\.count).max() ?? 0
        return CGSize(
            width: min(max(CGFloat(longest) * 9 + 60, 380), 640),
            height: min(max(CGFloat(lines.count) * 20 + 90, 220), 520),
        )
    }

    /// 放在鼠标所在屏幕的正中间（用户要求：位置固定，不跟着截图跑）
    private func place(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let visible = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        window.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
    }
}
