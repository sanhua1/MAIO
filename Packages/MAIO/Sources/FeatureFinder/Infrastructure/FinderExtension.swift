import Foundation

/// MAIO 的 Finder 右键菜单扩展是否启用（pluginkit：系统设置 › 通用 › 登录项与扩展 里的同一个开关）
enum FinderExtension {
    static let bundleID = "app.maio.MAIO.FinderSync"

    enum Status: Equatable {
        case enabled
        case disabled
        /// 系统还没登记这个扩展（MAIO 不在"应用程序"里、或刚装好还没被系统发现）
        case missing
    }

    static func status() async -> Status {
        let output = await pluginkit(["-m", "-i", bundleID])
        guard let line = output.split(separator: "\n").first(where: { $0.contains(bundleID) }) else { return .missing }
        return line.hasPrefix("+") ? .enabled : .disabled
    }

    static func setEnabled(_ enabled: Bool) async {
        _ = await pluginkit(["-e", enabled ? "use" : "ignore", "-i", bundleID])
    }

    private static func pluginkit(_ arguments: [String]) async -> String {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(filePath: "/usr/bin/pluginkit")
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(bytes: data, encoding: .utf8) ?? ""
        }.value
    }
}
