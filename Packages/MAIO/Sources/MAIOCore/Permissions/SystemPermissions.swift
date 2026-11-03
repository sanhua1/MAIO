import AppKit
import ApplicationServices
import CoreGraphics
import MAIOKit

/// 系统权限（TCC）的检测与申请。
@MainActor
public final class SystemPermissions: PermissionService {
    public init() {}

    public func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: AXIsProcessTrusted()
        case .inputMonitoring: CGPreflightListenEventAccess()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        }
    }

    public func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            let key = "AXTrustedCheckOptionPrompt" // kAXTrustedCheckOptionPrompt
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        openSystemSettings(for: permission)
    }

    public func openSystemSettings(for permission: Permission) {
        let anchor = switch permission {
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .screenRecording: "Privacy_ScreenCapture"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
