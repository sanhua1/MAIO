import AppKit

/// 读取剪贴板里的图片（贴剪贴板内容，spec F12）：图片、图片文件，或者把文字渲染成图片。
enum PasteboardImage {
    struct Content {
        let image: CGImage
        /// 每 pt 的像素数
        let scale: CGFloat
        /// 是不是由文字渲染出来的
        let isText: Bool
    }

    @MainActor static func read(from pasteboard: NSPasteboard = .general, screenScale: CGFloat) -> Content? {
        if let image = NSImage(pasteboard: pasteboard), let content = content(of: image) {
            return content
        }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingContentsConformToTypes: ["public.image"]]
        if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: options)?.first as? URL,
           let image = NSImage(contentsOf: url), let content = content(of: image) {
            return content
        }
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return render(text: text, scale: screenScale)
        }
        return nil
    }

    /// 读取图片文件（剪贴板历史右键贴图时传来的临时文件）
    static func read(fileAt url: URL) -> Content? {
        NSImage(contentsOf: url).flatMap(content(of:))
    }

    /// NSImage 的 size 已经按 DPI 换算成 pt（Retina 截图是像素的一半）
    private static func content(of image: NSImage) -> Content? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil), image.size.width > 0 else {
            return nil
        }
        return Content(image: cgImage, scale: CGFloat(cgImage.width) / image.size.width, isText: false)
    }

    /// 文字渲染成白底黑字的图片，最宽 640 pt，自动换行
    static func render(text: String, scale: CGFloat) -> Content? {
        let padding: CGFloat = 12
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black,
        ])
        let bounds = string.boundingRect(
            with: CGSize(width: 640, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading],
        )
        let size = CGSize(width: ceil(bounds.width) + padding * 2, height: ceil(bounds.height) + padding * 2)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
            bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        string.draw(
            with: CGRect(x: padding, y: padding, width: 640, height: bounds.height + 1),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
        )
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage().map { Content(image: $0, scale: scale, isText: true) }
    }
}

/// 旋转图片（贴图旋转后复制、保存）
enum ImageRotation {
    static func rotated(_ image: CGImage, quarterTurns: Int) -> CGImage? {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }
        let swap = turns % 2 == 1
        let width = swap ? image.height : image.width
        let height = swap ? image.width : image.height
        guard let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,
        ) else { return nil }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        // CGContext 原点在左下，顺时针旋转是负角度
        context.rotate(by: -CGFloat(turns) * .pi / 2)
        context.draw(image, in: CGRect(
            x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
            width: CGFloat(image.width), height: CGFloat(image.height),
        ))
        return context.makeImage()
    }
}
