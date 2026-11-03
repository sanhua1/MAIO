import Foundation

/// "打开 App" 的目标：bundle ID 或 .app 路径。
enum AppTarget: Equatable {
    case bundleID(String)
    case path(String)

    init(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasSuffix(".app") {
            self = .path((trimmed as NSString).expandingTildeInPath)
        } else if !trimmed.isEmpty {
            self = .bundleID(trimmed)
        } else {
            throw TargetError.empty
        }
    }
}

enum TargetError: Error, Equatable { case empty }

/// "打开网址或文件"：有 scheme 的按 URL 处理，其余按本地路径处理。
enum URLTarget {
    static func resolve(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return URL(filePath: (trimmed as NSString).expandingTildeInPath)
        }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }
}

/// 需要在子进程中执行的任务。
enum ProcessJob: Equatable {
    case shell(script: String)
    case appleScript(source: String)
    case shortcut(name: String)

    var executable: String {
        switch self {
        case .shell: "/bin/zsh"
        case .appleScript: "/usr/bin/osascript"
        case .shortcut: "/usr/bin/shortcuts"
        }
    }

    var arguments: [String] {
        switch self {
        case let .shell(script): ["-lc", script]
        case let .appleScript(source): ["-e", source]
        case let .shortcut(name): ["run", name]
        }
    }
}

struct ProcessResult: Equatable, Sendable {
    var exitCode: Int32
    var output: String
    var error: String

    /// 用于提示的简短文本：优先错误输出，最多 300 个字符。
    var summary: String {
        let text = (exitCode != 0 && !error.isEmpty ? error : output)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 300 ? String(text.prefix(300)) + "…" : text
    }
}
