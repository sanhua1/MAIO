import Darwin
import Foundation

/// 索引范围：默认排除哪些目录、有没有完全磁盘访问权限、扫哪些设备。
enum IndexConfiguration {
    /// 系统目录、其他卷、临时文件、缓存（参考 Cardinal useIgnorePaths.ts 和 oil-find IndexConfig.swift）
    static func defaultExcludedPaths(home: String) -> [String] {
        [
            "/System", "/Volumes", "/Network", "/dev", "/cores", "/private/var", tempFolder, "/Library/Caches",
            home + "/Library/Caches", home + "/Library/Logs", home + "/Library/CloudStorage", home + "/Library/Metadata",
            home + "/Library/Biome", home + "/.Trash",
        ]
    }

    /// `/tmp` 的真实位置（设置里可以打开索引）
    static let tempFolder = "/private/tmp"

    static let defaultExcludedNames: Set<String> = [
        ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems", ".Trashes",
    ]

    /// 受系统隐私保护的位置。没有完全磁盘访问权限时不扫，否则每个位置都会弹一次授权窗口
    static func protectedPaths(home: String) -> [String] {
        [
            "Desktop", "Documents", "Downloads", "Library/Mail", "Library/Messages", "Library/Safari",
            "Library/Containers", "Library/Group Containers", "Library/Daemon Containers",
            "Library/Application Support/AddressBook",
            "Library/Calendars", "Library/Cookies", "Library/HomeKit", "Library/Suggestions", "Library/Mobile Documents",
            "Library/Reminders", "Library/Accounts", "Library/IdentityServices", "Library/Sharing", "Library/Trial",
            "Pictures/Photos Library.photoslibrary",
        ].map { home + "/" + $0 }
    }

    /// 只有完全磁盘访问才能读、读不到时系统**不弹授权窗口**的位置（桌面、文稿、下载会弹，不能拿来试）。
    /// 没有公开接口能直接查这个权限，只能试读受保护的数据（Apple DTS 的建议）。
    /// 以前只看 `~/Library/Application Support/com.apple.TCC`：macOS 27 上这个目录不存在了，永远判成没有权限。
    static func fullDiskAccessProbes(home: String) -> [String] {
        [
            "Library/Safari", "Library/Mail", "Library/Messages", "Library/Cookies",
            "Library/Application Support/com.apple.TCC",
        ].map { home + "/" + $0 } + ["/Library/Application Support/com.apple.TCC"]
    }

    enum ProbeResult: Equatable {
        case readable
        case denied
        /// 不存在等其他错误：说明不了什么
        case unknown
    }

    /// 有一个位置能读就有权限；被拒绝就没有；都说明不了时按没有处理（不去碰会弹窗的位置）
    static func hasFullDiskAccess(_ results: some Sequence<ProbeResult>) -> Bool {
        for result in results {
            switch result {
            case .readable: return true
            case .denied: return false
            case .unknown: continue
            }
        }
        return false
    }

    static func hasFullDiskAccess(home: String = NSHomeDirectory()) -> Bool {
        hasFullDiskAccess(fullDiskAccessProbes(home: home).lazy.map(probe))
    }

    private static func probe(_ path: String) -> ProbeResult {
        guard let directory = opendir(path) else {
            return errno == EPERM || errno == EACCES ? .denied : .unknown
        }
        closedir(directory)
        return .readable
    }

    /// 系统卷和数据卷（`/Users` 等通过 firmlink 指向数据卷）
    static func devices() -> Set<Int32> {
        Set(["/", "/System/Volumes/Data"].compactMap { path in
            var info = stat()
            return stat(path, &info) == 0 ? info.st_dev : nil
        })
    }

    static func options(
        extraExcluded: [String], indexPackageContents: Bool, fullDiskAccess: Bool, indexTempFolder: Bool = false,
        home: String = NSHomeDirectory(),
    ) -> ScanOptions {
        var excluded = Set(defaultExcludedPaths(home: home) + extraExcluded)
        if indexTempFolder {
            excluded.remove(tempFolder)
        }
        if !fullDiskAccess {
            excluded.formUnion(protectedPaths(home: home))
        }
        return ScanOptions(
            excludedPaths: excluded, excludedNames: defaultExcludedNames, indexPackageContents: indexPackageContents,
            threads: max(2, min(8, ProcessInfo.processInfo.activeProcessorCount / 2)), homePath: home,
        )
    }

    /// 设置的指纹：变了就要重扫
    static func fingerprint(_ options: ScanOptions) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        let text = options.excludedPaths.sorted().joined(separator: "\n") + "|" + options.excludedNames.sorted()
            .joined(separator: "\n") + "|\(options.indexPackageContents)|\(options.homePath)|" + EntryFlags.signature
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

extension EntryFlags {
    /// 标志规则的签名：改了依赖目录名单、包扩展名，旧索引里的标志就不对了，要重扫
    static var signature: String {
        "v1|" + dependencyNames.sorted().joined(separator: ",") + "|" + packageExtensions.sorted().joined(separator: ",")
    }
}
