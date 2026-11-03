import AppKit
import MAIOKit

/// 全屏 / 窗口截图（直接复制并写入历史）、截图历史窗口。
extension ScreenshotController {
    func captureFullScreen() async {
        guard session == nil, ensurePermission() else { return }
        let mouse = CaptureSession.globalMouseLocation()
        let displays = DisplayInfo.all()
        guard let display = displays.first(where: { $0.bounds.contains(mouse) }) ?? displays.first else { return }
        do {
            let image = try await ScreenCapturer.capture(rect: display.bounds)
            let result = CaptureResult(
                original: image, rendered: nil, annotations: [], scale: CGFloat(image.width) / display.bounds.width,
                frame: display.bounds,
            )
            await output(result, action: .copy, sourceApp: Self.frontmostOtherApp()?.bundleIdentifier)
            context.overlay.showHUD("已复制全屏截图", symbol: "camera.viewfinder")
        } catch {
            report(error)
        }
    }

    func captureFrontWindow() async {
        guard session == nil, ensurePermission() else { return }
        guard let app = Self.frontmostOtherApp(),
              let window = WindowSnapshot.current().first(where: { $0.pid == app.processIdentifier && $0.layer == 0 })
        else {
            context.overlay.showHUD("没有可以截取的窗口", symbol: "macwindow")
            return
        }
        do {
            let image = try await ScreenCapturer.captureWindow(id: window.id)
            let result = CaptureResult(
                original: image, rendered: nil, annotations: [], scale: CGFloat(image.width) / max(window.frame.width, 1),
                frame: window.frame,
            )
            await output(result, action: .copy, sourceApp: app.bundleIdentifier)
            context.overlay.showHUD("已复制窗口截图", symbol: "macwindow")
        } catch {
            report(error)
        }
    }

    // MARK: 截图历史

    func showHistory() {
        guard let history else {
            context.overlay.showError("截图历史不可用")
            return
        }
        if historyWindow == nil {
            historyWindow = HistoryWindowController(store: history, actions: historyActions)
        }
        historyWindow?.show()
    }

    private var historyActions: HistoryBrowserModel.Actions {
        HistoryBrowserModel.Actions(
            pin: { [weak self] id in Task { await self?.pinRecord(id) } },
            copy: { [weak self] id in Task { await self?.copyRecord(id) } },
            edit: { [weak self] id in Task { await self?.beginEdit(recordID: id, pin: nil) } },
            recognize: { [weak self] id, translate in Task { await self?.recognizeRecord(id, translate: translate) } },
        )
    }

    func copyRecord(_ id: String) async {
        guard let history, let record = await history.record(id: id),
              let data = try? await Data(contentsOf: history.finalImageURL(for: record)) else { return }
        ImageExporter.copyToPasteboard(png: data)
        context.overlay.showHUD("已复制截图", symbol: "doc.on.doc")
    }
}
