import AppKit
import MAIOUI
import SwiftUI

/// 新版本下载好后的询问窗口：版本号、更新内容、「安装并重启」「稍后」「跳过这个版本」。
@MainActor
final class UpdatePromptWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let updater: Updater

    init(updater: Updater) {
        self.updater = updater
    }

    func show(_ prepared: UpdateInstaller.Prepared) {
        window?.close()
        let view = UpdatePromptView(
            prepared: prepared,
            current: updater.currentVersion?.description ?? "开发版",
            install: { [weak self] in
                self?.close()
                self?.updater.install(prepared)
            },
            later: { [weak self] in self?.close() },
            skip: { [weak self] in
                self?.updater.skip(prepared)
                self?.close()
            },
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable], backing: .buffered, defer: false,
        )
        window.title = "MAIO 更新"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.delegate = self
        self.window = window
        AppActivation.activateForcibly()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_: Notification) {
        window = nil
    }
}

private struct UpdatePromptView: View {
    let prepared: UpdateInstaller.Prepared
    let current: String
    let install: () -> Void
    let later: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAIO \(prepared.release.version.description) 已下载好").font(.headline)
                    Text("当前版本 \(current)。安装后 MAIO 会自动重启，设置和数据都会保留。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView {
                Text(notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(.background.opacity(0.6), in: .rect(cornerRadius: 8))
            HStack {
                Button("跳过这个版本", action: skip)
                if let page = prepared.release.pageURL {
                    Link("在网页上查看", destination: page)
                }
                Spacer()
                Button("稍后", action: later).keyboardShortcut(.cancelAction)
                Button("安装并重启", action: install).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 460, height: 360)
    }

    private var notes: AttributedString {
        let text = prepared.release.notes.isEmpty ? "（没有更新说明）" : prepared.release.notes
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
