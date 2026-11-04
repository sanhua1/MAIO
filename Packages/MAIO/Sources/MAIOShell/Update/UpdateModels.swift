import Foundation

/// 版本号（"0.1.10" 这种点分数字，比较时逐段按数字比）。标签前面的 "v" 会去掉。
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let parts: [Int]
    let description: String

    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.first == "v" || trimmed.first == "V" {
            trimmed.removeFirst()
        }
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = pieces.compactMap { Int($0) }
        guard !numbers.isEmpty, numbers.count == pieces.count else { return nil }
        parts = numbers
        description = trimmed
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0 ..< max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// 一次发布（来自 GitHub Releases 的 latest 接口）
struct ReleaseInfo: Equatable, Sendable {
    let version: AppVersion
    let notes: String
    let pageURL: URL?
    let assetURL: URL
    let assetSize: Int
    /// 小写十六进制；GitHub 为上传的附件算好的 SHA-256（旧发布可能没有）
    let sha256: String?

    enum ParseError: Error, LocalizedError, Equatable {
        case invalidJSON
        case invalidVersion(String)
        case missingAsset(String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON: "更新信息格式不对"
            case let .invalidVersion(tag): "无法识别的版本号：\(tag)"
            case let .missingAsset(name): "发布里没有安装包 \(name)"
            }
        }
    }

    /// 解析 `GET /repos/<owner>/<repo>/releases/latest` 的返回。安装包必须叫 `MAIO-<版本>.zip`（`make release` 的输出）。
    static func parse(_ data: Data) throws -> ReleaseInfo {
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw ParseError.invalidJSON
        }
        guard !release.draft, !release.prerelease, let version = AppVersion(release.tag_name) else {
            throw ParseError.invalidVersion(release.tag_name)
        }
        let name = "MAIO-\(version).zip"
        guard let asset = release.assets.first(where: { $0.name == name }),
              let url = URL(string: asset.browser_download_url) else { throw ParseError.missingAsset(name) }
        let digest = asset.digest.flatMap { value -> String? in
            guard value.hasPrefix("sha256:") else { return nil }
            return String(value.dropFirst("sha256:".count)).lowercased()
        }
        return ReleaseInfo(
            version: version,
            notes: release.body ?? "",
            pageURL: release.html_url.flatMap(URL.init(string:)),
            assetURL: url,
            assetSize: asset.size,
            sha256: digest,
        )
    }

    /// GitHub 接口的字段名（下划线风格，保持原样以便直接解码）
    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int
            let browser_download_url: String
            let digest: String?
        }

        let tag_name: String
        let body: String?
        let html_url: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
}

/// 更新设置与记录（config/update.json）
struct UpdateSettings: Codable, Equatable {
    /// 自动检查（启动后和每 24 小时），发现新版本自动下载，下载好后询问是否安装
    var automaticChecks = true
    var lastCheck: Date?
    /// 用户选了"跳过这个版本"；手动检查时不受影响
    var skippedVersion: String?

    static let path = "config/update.json"
    static let checkInterval: TimeInterval = 24 * 60 * 60

    func isCheckDue(now: Date) -> Bool {
        guard automaticChecks else { return false }
        guard let lastCheck else { return true }
        // 系统时间被往回调过时也重新检查
        return now.timeIntervalSince(lastCheck) >= Self.checkInterval || now < lastCheck
    }
}
