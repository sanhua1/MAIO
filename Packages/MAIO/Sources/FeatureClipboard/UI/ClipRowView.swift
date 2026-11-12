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
        .frame(height: item.kind == .image || item.hasThumbnail ? 52 : 32)
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
            withImageText(thumbnail(fallback: "图片"))
        case .files:
            if item.hasThumbnail {
                // 复制的图片文件：显示缩略图，文件名等缩略图加载好之前当占位
                withImageText(thumbnail(fallback: item.summary))
            } else {
                Label(item.summary, systemImage: "doc").lineLimit(1).truncationMode(.middle)
            }
        case .text, .richText:
            Text(item.summary).lineLimit(1).truncationMode(.tail)
        }
    }

    /// 搜索命中图片里的文字时，在缩略图右边显示命中处附近的一段
    @ViewBuilder private func withImageText(_ thumbnail: some View) -> some View {
        if let text = item.textInImage {
            HStack(spacing: 8) {
                thumbnail
                Label(text, systemImage: "text.viewfinder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help("图片里的文字")
            }
        } else {
            thumbnail
        }
    }

    @ViewBuilder private func thumbnail(fallback: String) -> some View {
        if let thumbnail = model.thumbnail(for: item) {
            let size = Self.displaySize(for: thumbnail)
            Image(nsImage: thumbnail)
                .resizable()
                // 几个像素的小图在 Retina 上放大 2 倍，按像素块画，不糊成一团
                .interpolation(size.width < 32 || size.height < 32 ? .none : .high)
                .frame(width: size.width, height: size.height)
            // 不切圆角：原图是直角的长方形，圆角看着别扭（用户选择）
        } else {
            Label(fallback, systemImage: "photo")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
    }

    /// 列表里缩略图的最大显示尺寸
    static let maxThumbnailSize = CGSize(width: 200, height: 44)

    /// 按原图自己的大小显示，最大 200×44。
    /// 小图不放大（几个像素的图被拉成 44 pt 会显得很大），大图等比缩小。
    static func displaySize(for image: NSImage) -> CGSize {
        let natural = image.size
        guard natural.width > 0, natural.height > 0 else { return maxThumbnailSize }
        let scale = min(1, min(maxThumbnailSize.width / natural.width, maxThumbnailSize.height / natural.height))
        return CGSize(width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded())
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
    let content: ClipPreviewContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            bodyContent
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private var item: ClipItem {
        content.item
    }

    private var payload: ClipPayload {
        content.payload
    }

    /// 图片文件用文件名当标题，比"文件"更有用
    private var title: String {
        item.kind == .files && content.image != nil ? item.summary : item.kind.title
    }

    @ViewBuilder private var bodyContent: some View {
        switch item.kind {
        case .image:
            image
        case .files:
            if content.image != nil {
                image
            } else {
                fileList
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

    @ViewBuilder private var image: some View {
        if let image = content.image {
            if image.size.width < 64 || image.size.height < 64 {
                // 几个像素的小图不铺满预览，最多放大 8 倍，按像素块显示
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: max(image.size.width, 1) * 8, height: max(image.size.height, 1) * 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Text("图片无法显示").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var fileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(payload.fileURLs, id: \.self) { url in
                    Text(url.path).font(.callout.monospaced()).textSelection(.enabled)
                        .foregroundStyle(FileManager.default.fileExists(atPath: url.path) ? .primary : .secondary)
                }
            }
        }
    }

    private var details: String {
        var parts = [ByteFormat.string(item.byteSize)]
        if let size = content.pixelSize {
            parts.insert("\(Int(size.width))×\(Int(size.height))", at: 0)
        }
        if let text = payload.plainText, item.kind == .text || item.kind == .richText {
            parts.insert("\(text.count) 字", at: 0)
        }
        parts.append(item.createdAt.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}
