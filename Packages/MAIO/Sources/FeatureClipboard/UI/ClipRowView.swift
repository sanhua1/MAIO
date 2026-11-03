import AppKit
import SwiftUI

/// 一行：来源 App 图标 · 内容摘要（图片显示缩略图）· 快速粘贴编号 / 固定标记 · 时间。
struct ClipRowView: View {
    let item: ClipItem
    let model: ClipboardViewModel
    let isSelected: Bool
    let quickSlot: Int?

    var body: some View {
        HStack(spacing: 8) {
            appIcon
            content
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(height: item.kind == .image ? 52 : 32)
        .background(isSelected ? Color.accentColor.opacity(0.3) : .clear, in: .rect(cornerRadius: 7))
        .contentShape(.rect)
    }

    @ViewBuilder private var appIcon: some View {
        if let icon = model.icon(forApp: item.sourceBundleID) {
            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: "app.dashed").frame(width: 18, height: 18).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            if let thumbnail = model.thumbnail(for: item) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 44, alignment: .leading)
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                Label("图片", systemImage: "photo").foregroundStyle(.secondary)
            }
        case .files:
            Label(item.summary, systemImage: "doc").lineLimit(1).truncationMode(.middle)
        case .text, .richText:
            Text(item.summary).lineLimit(1).truncationMode(.tail)
        }
    }

    private var trailing: some View {
        HStack(spacing: 6) {
            if item.isPinned {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange)
            }
            Text(item.lastUsedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let quickSlot {
                Text("⌘\(quickSlot)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }
        }
    }
}

/// 一条历史的右键菜单
struct ClipContextMenu: View {
    let item: ClipItem
    let model: ClipboardViewModel

    var body: some View {
        Button("粘贴") { model.perform(.paste, on: item) }
        if item.kind == .richText {
            Button("粘贴为纯文本") { model.perform(.pastePlainText, on: item) }
        }
        Button("复制到剪贴板（不粘贴）") { model.perform(.copy, on: item) }
        Divider()
        if item.kind != .files {
            Button("贴图（钉在屏幕上）") { model.perform(.pinToScreen, on: item) }
        }
        if item.kind == .text || item.kind == .richText {
            Button("翻译") { model.perform(.translate, on: item) }
        }
        Button("预览（空格）") { model.perform(.preview, on: item) }
        Divider()
        Button(item.isPinned ? "取消固定" : "固定") { model.perform(.togglePin, on: item) }
        Button("删除（⌘⌫）", role: .destructive) { model.perform(.delete, on: item) }
    }
}

/// 预览：完整文字（可选择）、大图或文件列表。
struct ClipPreviewView: View {
    let item: ClipItem
    let payload: ClipPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.kind.title).font(.headline)
                Spacer()
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            if let data = payload.data(PasteType.png) ?? payload.data(PasteType.tiff), let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .files:
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(payload.fileURLs, id: \.self) { url in
                        Text(url.path).font(.callout.monospaced()).textSelection(.enabled)
                            .foregroundStyle(FileManager.default.fileExists(atPath: url.path) ? .primary : .secondary)
                    }
                }
            }
        case .text, .richText:
            ScrollView {
                Text(payload.plainText ?? "")
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var details: String {
        var parts = [ByteFormat.string(item.byteSize)]
        if item.kind == .image, let data = payload.data(PasteType.png) ?? payload.data(PasteType.tiff),
           let size = Thumbnails.pixelSize(data) {
            parts.insert("\(Int(size.width))×\(Int(size.height))", at: 0)
        }
        if let text = payload.plainText, item.kind != .image {
            parts.insert("\(text.count) 字", at: 0)
        }
        parts.append(item.createdAt.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}
