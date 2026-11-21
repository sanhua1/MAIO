import AppKit
import CoreGraphics

/// 显示器插拔、分辨率变化、唤醒时通知重新扫描。
@MainActor
final class DisplayWatcher {
    private var onChange: (@MainActor (Duration) -> Void)?
    private var observers: [NSObjectProtocol] = []
    /// 交给 C 回调的中转对象：回调派发到主线程时 watcher 可能已经释放，所以只弱引用它
    private var token: Unmanaged<WatcherToken>?

    /// `onChange` 的参数是建议的延迟：显示器刚接上、刚唤醒时 DDC 还没准备好
    func start(onChange: @escaping @MainActor (Duration) -> Void) {
        stop()
        self.onChange = onChange
        let box = WatcherToken()
        box.watcher = self
        let token = Unmanaged.passRetained(box)
        if CGDisplayRegisterReconfigurationCallback(displayReconfigured, token.toOpaque()) == .success {
            self.token = token
        } else {
            token.release()
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?(.seconds(2)) }
            })
        }
    }

    func stop() {
        if let token {
            CGDisplayRemoveReconfigurationCallback(displayReconfigured, token.toOpaque())
            token.release()
            self.token = nil
        }
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        onChange = nil
    }

    fileprivate func reconfigured() {
        onChange?(.seconds(1.5))
    }
}

/// 只在主线程读写 `watcher`
private final class WatcherToken: @unchecked Sendable {
    weak var watcher: DisplayWatcher?
}

/// 每次变化系统会先后各调一次（开始前带 beginConfigurationFlag、完成后不带），只关心完成后的那次
private func displayReconfigured(
    _: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ info: UnsafeMutableRawPointer?,
) {
    guard let info, !flags.contains(.beginConfigurationFlag) else { return }
    let token = Unmanaged<WatcherToken>.fromOpaque(info).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated { token.watcher?.reconfigured() }
    }
}

/// 系统设置里的页面（⌥ + 音量 / 亮度键）
enum SystemSettingsPage: String {
    case sound = "com.apple.Sound-Settings.extension"
    case displays = "com.apple.Displays-Settings.extension"

    @MainActor
    static func open(_ page: Self) {
        guard let url = URL(string: "x-apple.systempreferences:\(page.rawValue)") else { return }
        NSWorkspace.shared.open(url)
    }
}
