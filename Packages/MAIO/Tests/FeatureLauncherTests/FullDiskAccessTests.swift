@testable import FeatureLauncher
import Foundation
import Testing

struct FullDiskAccessTests {
    typealias Probe = IndexConfiguration.ProbeResult

    @Test func `first conclusive probe decides`() {
        #expect(IndexConfiguration.hasFullDiskAccess([Probe.unknown, .readable, .denied]))
        #expect(!IndexConfiguration.hasFullDiskAccess([Probe.unknown, .denied, .readable]))
    }

    /// macOS 27 上 TCC 目录不存在：只要别的受保护位置能读，就是有权限（以前这里永远是"没有"）
    @Test func `missing TCC folder does not mean no access`() {
        #expect(IndexConfiguration.hasFullDiskAccess([Probe.readable, .unknown]))
        #expect(IndexConfiguration.hasFullDiskAccess([Probe.unknown, .unknown, .unknown, .unknown, .unknown, .readable]))
    }

    /// /tmp 默认不索引；打开开关后不再排除，索引指纹变了（会重扫）
    @Test func `temp folder is excluded unless enabled`() {
        let off = IndexConfiguration.options(
            extraExcluded: [],
            indexPackageContents: false,
            fullDiskAccess: true,
            home: "/Users/u",
        )
        let on = IndexConfiguration.options(
            extraExcluded: [], indexPackageContents: false, fullDiskAccess: true, indexTempFolder: true, home: "/Users/u",
        )
        #expect(off.excludedPaths.contains("/private/tmp"))
        #expect(!on.excludedPaths.contains("/private/tmp"))
        #expect(on.excludedPaths.contains("/private/var"))
        #expect(IndexConfiguration.fingerprint(off) != IndexConfiguration.fingerprint(on))
    }

    @Test func `nothing conclusive counts as no access`() {
        #expect(!IndexConfiguration.hasFullDiskAccess([Probe.unknown, .unknown]))
        #expect(!IndexConfiguration.hasFullDiskAccess([Probe]()))
    }

    /// 探测的位置里不能有没权限时会弹授权窗口的（桌面、文稿、下载……）
    @Test func `probes never touch folders that prompt`() {
        let home = "/Users/test"
        let prompting = ["Desktop", "Documents", "Downloads", "Pictures"].map { home + "/" + $0 }
        for path in IndexConfiguration.fullDiskAccessProbes(home: home) {
            #expect(!prompting.contains { path.hasPrefix($0) })
        }
    }
}
