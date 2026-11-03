import AppKit
import os
import ScreenCaptureKit

/// 一个显示器。`bounds` 是全局坐标（左上角原点，pt），与 CGWindowList 一致。
struct DisplayInfo: Sendable, Equatable {
    var id: CGDirectDisplayID
    var bounds: CGRect

    /// 当前所有显示器（与 NSScreen 一一对应）。
    @MainActor static func all() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            screen.displayID.map { DisplayInfo(id: $0, bounds: CGDisplayBounds($0)) }
        }
    }
}

/// 冻结的显示器画面。
struct FrozenDisplay: @unchecked Sendable {
    let display: DisplayInfo
    let image: CGImage

    /// 每 pt 对应的像素数（按实际截到的图计算，不依赖 backingScaleFactor）
    var scale: CGFloat {
        display.bounds.width > 0 ? CGFloat(image.width) / display.bounds.width : 1
    }
}

enum CaptureError: LocalizedError {
    case noImage
    case timeout

    var errorDescription: String? {
        switch self {
        case .noImage: "系统没有返回图片"
        case .timeout: "系统截图接口超时没有响应（屏幕锁定时会这样）"
        }
    }
}

/// 用 ScreenCaptureKit 截图（ADR-0011：macOS 26 的 captureScreenshot(rect:)，可以不带鼠标指针）。
enum ScreenCapturer {
    /// 截图接口的最长等待时间。锁屏时系统截图接口不返回，不加超时的话之后的截图都会被卡住。
    static let timeout: Duration = .seconds(2)

    static func capture(_ displays: [DisplayInfo]) async throws -> [FrozenDisplay] {
        try await withTimeout(timeout) { try await captureAll(displays) }
    }

    private static func captureAll(_ displays: [DisplayInfo]) async throws -> [FrozenDisplay] {
        try await withThrowingTaskGroup(of: FrozenDisplay.self) { group in
            for display in displays {
                group.addTask { try await FrozenDisplay(display: display, image: screenshot(rect: display.bounds)) }
            }
            var result: [FrozenDisplay] = []
            for try await frozen in group {
                result.append(frozen)
            }
            return displays.compactMap { display in result.first { $0.display.id == display.id } }
        }
    }

    static func capture(rect: CGRect) async throws -> CGImage {
        try await withTimeout(timeout) { try await screenshot(rect: rect) }
    }

    private static func screenshot(rect: CGRect) async throws -> CGImage {
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr
        let output = try await SCScreenshotManager.captureScreenshot(rect: rect, configuration: configuration)
        guard let image = output.sdrImage else { throw CaptureError.noImage }
        return image
    }

    /// 第一次调用比之后慢约 60 ms（ADR-0011 实验），功能启用时先截一小块预热。
    static func prewarm() async {
        _ = try? await capture(rect: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// 截取单个窗口（保留透明圆角，不带阴影）。
    static func captureWindow(id: CGWindowID) async throws -> CGImage {
        try await withTimeout(timeout) { try await windowImage(id: id) }
    }

    private static func windowImage(id: CGWindowID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.noImage }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

/// 超时就返回错误。不能用任务组实现：任务组要等全部子任务结束，而系统截图接口不响应取消。
func withTimeout<T: Sendable>(
    _ timeout: Duration, _ operation: @escaping @Sendable () async throws -> T,
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let pending = OSAllocatedUnfairLock<CheckedContinuation<T, any Error>?>(initialState: continuation)
        let resume: @Sendable (Result<T, any Error>) -> Void = { result in
            pending.withLock { value in
                let current = value
                value = nil
                return current
            }?.resume(with: result)
        }
        Task {
            do {
                try await resume(.success(operation()))
            } catch {
                resume(.failure(error))
            }
        }
        Task {
            try? await Task.sleep(for: timeout)
            resume(.failure(CaptureError.timeout))
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
