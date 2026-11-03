import AppKit
import MAIOKit
import MAIOUI
import SwiftUI

/// OverlayService 的实现：同一时间只显示一个 HUD，新的替换旧的。
@MainActor
final class HUDOverlay: OverlayService {
    private var panel: FloatingPanel<HUDView>?
    private var hideTask: Task<Void, Never>?

    func showHUD(_ message: String, symbol: String?) {
        show(HUDView(message: message, symbol: symbol), duration: .seconds(1.6))
    }

    func showError(_ message: String) {
        show(HUDView(message: message, style: .error), duration: .seconds(4))
    }

    private func show(_ view: HUDView, duration: Duration) {
        hideTask?.cancel()
        panel?.orderOut(nil)
        let panel = FloatingPanel(rootView: view)
        panel.place(relativeX: 0.5, relativeY: 0.2)
        panel.orderFrontRegardless()
        self.panel = panel
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }
}
