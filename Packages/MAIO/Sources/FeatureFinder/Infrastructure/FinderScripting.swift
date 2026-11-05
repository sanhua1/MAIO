import AppKit

enum FinderScriptError: Error, Equatable {
    /// 没有「自动化 › Finder」授权（-1743）
    case notAuthorized
    case failed(String)

    var message: String {
        switch self {
        case .notAuthorized: "需要允许 MAIO 控制 Finder：系统设置 › 隐私与安全性 › 自动化 › MAIO › Finder"
        case let .failed(reason): "Finder 没有响应：\(reason)"
        }
    }
}

/// 通过 AppleScript 让 Finder 做事（ADR-0017）。脚本在后台线程执行，不卡主线程；
/// 第一次执行时系统会弹出"自动化"授权。
enum FinderScripting {
    /// 当前位置：前台 Finder 窗口的文件夹；焦点在桌面时是桌面
    static func insertionFolder() async -> Result<URL, FinderScriptError> {
        let source = """
        tell application "Finder" to return POSIX path of (insertion location as alias)
        """
        return await run(source).map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// 在当前位置新建空文件并选中它（重名时加 " 2"、" 3"…），返回文件名
    static func newFile(named fileName: String) async -> Result<String, FinderScriptError> {
        let source = """
        tell application "Finder"
            set loc to insertion location
        \(uniqueNameScript(fileName))
            set newFile to make new file at loc with properties {name:fileName}
            select newFile
            return fileName
        end tell
        """
        return await run(source)
    }

    /// 文件夹里不重名的文件名（重名时加 " 2"、" 3"…）
    static func uniqueName(_ fileName: String, in folder: URL) async -> Result<String, FinderScriptError> {
        await run("""
        tell application "Finder"
            set loc to \(folderReference(folder))
        \(uniqueNameScript(fileName))
            return fileName
        end tell
        """)
    }

    /// 让 Finder 把文件移进文件夹并选中（文件由 Finder 写入，MAIO 不需要那个文件夹的访问授权）
    static func moveIn(_ file: URL, to folder: URL) async -> Result<String, FinderScriptError> {
        await run("""
        tell application "Finder"
            set newFile to move (POSIX file "\(escape(file.path(percentEncoded: false)))" as alias) to \(folderReference(folder))
            select newFile
            return name of newFile
        end tell
        """)
    }

    private static func folderReference(_ folder: URL) -> String {
        "folder (POSIX file \"\(escape(folder.path(percentEncoded: false)))\" as alias)"
    }

    /// 在 Finder 的 tell 块里算出不重名的 fileName（变量 loc 是目标文件夹）
    private static func uniqueNameScript(_ fileName: String) -> String {
        let (base, ext) = split(fileName)
        return """
            set baseName to "\(escape(base))"
            set ext to "\(escape(ext))"
            set fileName to baseName & ext
            set i to 2
            repeat while exists item fileName of loc
                set fileName to baseName & " " & i & ext
                set i to i + 1
            end repeat
        """
    }

    static func split(_ fileName: String) -> (base: String, ext: String) {
        FileTemplates.split(fileName)
    }

    /// AppleScript 字符串字面量转义
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func run(_ source: String) async -> Result<String, FinderScriptError> {
        await Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else { return .failure(.failed("脚本无效")) }
            var error: NSDictionary?
            let output = script.executeAndReturnError(&error)
            if let error {
                let number = error[NSAppleScript.errorNumber] as? Int
                if number == -1743 {
                    return .failure(.notAuthorized)
                }
                let reason = error[NSAppleScript.errorMessage] as? String ?? "错误 \(number ?? 0)"
                return .failure(.failed(reason))
            }
            return .success(output.stringValue ?? "")
        }.value
    }
}
