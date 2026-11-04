import CryptoKit
import Foundation
import Security

/// 下载、校验、替换。只依赖 Foundation / Security / CryptoKit（便于单独编译做端到端测试）。
///
/// 安全：下载的 App 必须满足**当前正在运行的 MAIO 的签名要求**（designated requirement），
/// 也就是同一张证书签的、同一个 bundle ID，否则不安装。这同时保证了更新后辅助功能等授权继续有效
/// （系统按这条签名要求认 App），见 ADR-0016。
enum UpdateInstaller {
    enum Failure: Error, LocalizedError, Equatable {
        case checksumMismatch
        case unzipFailed(String)
        case appMissing
        case wrongApp(String)
        case signature(String)
        case notReplaceable(String)

        var errorDescription: String? {
            switch self {
            case .checksumMismatch: "下载的安装包校验值不对（可能下载不完整），已删除"
            case let .unzipFailed(reason): "解压失败：\(reason)"
            case .appMissing: "安装包里没有 MAIO.app"
            case let .wrongApp(reason): "安装包里的 App 不对：\(reason)"
            case let .signature(reason): "安装包的签名和当前 MAIO 不一致，不安装（\(reason)）"
            case let .notReplaceable(reason): reason
            }
        }
    }

    /// 准备好、可以安装的新版本
    struct Prepared: Equatable, Sendable {
        let release: ReleaseInfo
        /// 解压出来、已校验过的 MAIO.app
        let appURL: URL
    }

    /// 下载 → 校验 SHA-256 → 解压 → 校验 bundle ID、版本号、签名。workDirectory 每个版本一个，开始前清空。
    static func prepare(
        _ release: ReleaseInfo,
        workDirectory: URL,
        requirement: SecRequirement?,
        bundleID: String,
    ) async throws -> Prepared {
        let files = FileManager.default
        try? files.removeItem(at: workDirectory)
        try files.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        var request = URLRequest(url: release.assetURL)
        request.setValue("MAIO-Updater", forHTTPHeaderField: "User-Agent")
        let (downloaded, _) = try await URLSession.shared.download(for: request)
        let zip = workDirectory.appending(path: "MAIO.zip")
        try files.moveItem(at: downloaded, to: zip)
        if let expected = release.sha256, try sha256(of: zip) != expected {
            try? files.removeItem(at: workDirectory)
            throw Failure.checksumMismatch
        }
        let extracted = workDirectory.appending(path: "extracted", directoryHint: .isDirectory)
        try unzip(zip, to: extracted)
        let app = extracted.appending(path: "MAIO.app", directoryHint: .isDirectory)
        guard files.fileExists(atPath: app.path) else { throw Failure.appMissing }
        try verifyBundle(app, bundleID: bundleID, version: release.version)
        try verifySignature(app, requirement: requirement)
        return Prepared(release: release, appURL: app)
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func unzip(_ zip: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, directory.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Failure.unzipFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func verifyBundle(_ app: URL, bundleID: String, version: AppVersion) throws {
        guard let info = Bundle(url: app)?.infoDictionary else { throw Failure.wrongApp("读不到 Info.plist") }
        guard info["CFBundleIdentifier"] as? String == bundleID else {
            throw Failure.wrongApp("bundle ID 是 \(info["CFBundleIdentifier"] as? String ?? "空")")
        }
        guard let text = info["CFBundleShortVersionString"] as? String, AppVersion(text) == version else {
            throw Failure.wrongApp("版本号和发布不一致")
        }
    }

    /// requirement 为 nil 时用当前进程的签名要求
    static func verifySignature(_ app: URL, requirement: SecRequirement?) throws {
        guard let requirement = requirement ?? currentRequirement() else {
            throw Failure.signature("读不到当前 MAIO 的签名")
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw Failure.signature("读不到安装包的签名")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            throw Failure.signature(message)
        }
    }

    /// 当前运行的 MAIO 的签名要求。临时签名（ad-hoc）的版本要求的是本次编译的 cdhash，任何新版本都不会满足。
    static func currentRequirement() -> SecRequirement? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess
        else { return nil }
        return requirement
    }

    /// 当前 App 能不能被原地替换：不能在 App Translocation 的只读临时路径里运行，所在文件夹要可写
    static func checkReplaceable(_ app: URL) throws {
        if app.path.contains("/AppTranslocation/") {
            throw Failure.notReplaceable("MAIO 是从「下载」等位置直接打开的，系统把它放在了只读的临时位置。请先把 MAIO.app 拖进「应用程序」文件夹再打开")
        }
        let folder = app.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: folder) else {
            throw Failure.notReplaceable("没有权限修改 \(folder)，请手动下载安装")
        }
    }

    /// 等当前进程退出后，用新版本替换旧版本并打开；替换失败时恢复旧版本并打开，结果写进 resultFile。
    /// 用 /bin/sh 而不是 MAIO 自己：替换的时候 MAIO 必须已经退出。路径都作为参数传入，不拼进脚本。
    static func launchReplacement(new: URL, installedAt destination: URL, resultFile: URL) throws {
        let backup = destination.deletingLastPathComponent()
            .appending(path: ".MAIO-old-\(UUID().uuidString).app", directoryHint: .isDirectory)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [
            "-c", replaceScript, "maio-update",
            String(ProcessInfo.processInfo.processIdentifier), new.path, destination.path, backup.path, resultFile.path,
        ]
        try process.run()
    }

    /// $1 进程号  $2 新 App  $3 安装位置  $4 备份位置  $5 结果文件
    static let replaceScript = """
    i=0
    while kill -0 "$1" 2>/dev/null; do
      i=$((i+1)); [ "$i" -gt 300 ] && { echo "等待 MAIO 退出超时" > "$5"; exit 1; }
      sleep 0.1
    done
    if mv "$3" "$4"; then
      if mv "$2" "$3"; then
        rm -rf "$4"
        xattr -dr com.apple.quarantine "$3" 2>/dev/null
        echo ok > "$5"
      else
        mv "$4" "$3"
        echo "无法把新版本移到 $3" > "$5"
      fi
    else
      echo "无法移走旧版本 $3" > "$5"
    fi
    open "$3"
    """
}
