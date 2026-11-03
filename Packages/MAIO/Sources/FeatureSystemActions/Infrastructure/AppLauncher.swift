import AppKit
import MAIOKit

enum AppLauncher {
    @MainActor
    static func open(_ target: AppTarget) async throws {
        let url: URL
        switch target {
        case let .bundleID(bundleID):
            guard let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                throw CommandError.failed("找不到 App：\(bundleID)")
            }
            url = found
        case let .path(path):
            guard FileManager.default.fileExists(atPath: path) else {
                throw CommandError.failed("找不到 App：\(path)")
            }
            url = URL(filePath: path)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
