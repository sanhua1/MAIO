import Foundation
@testable import MAIOShell
import Testing

struct AppVersionTests {
    private func version(_ text: String) throws -> AppVersion {
        try #require(AppVersion(text))
    }

    @Test func `compares numerically segment by segment`() throws {
        #expect(try version("0.1.10") > version("0.1.9"))
        #expect(try version("v0.2.0") > version("0.1.99"))
        #expect(try version("1.0") == version("1.0.0"))
        #expect(try version("v0.1.1").description == "0.1.1")
    }

    @Test func `rejects non numeric versions`() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("0.1.0-beta") == nil)
        #expect(AppVersion("1..2") == nil)
    }
}

struct ReleaseInfoTests {
    /// 字段和真实接口一致（取自 v0.1.0 的 releases/latest 返回）
    private func json(
        tag: String = "v0.1.1",
        asset: String = "MAIO-0.1.1.zip",
        digest: String? = "sha256:ABCDEF",
        prerelease: Bool = false,
    ) -> Data {
        let digestField = digest.map { "\"digest\": \"\($0)\"," } ?? ""
        return Data("""
        {"tag_name": "\(tag)", "name": "MAIO", "body": "## 更新\\n- 修复", "html_url": "https://github.com/sanhua1/MAIO/releases/tag/\(tag)",
         "draft": false, "prerelease": \(prerelease), "assets": [
          {"name": "\(asset)", "size": 3765100, \(digestField)
           "browser_download_url": "https://github.com/sanhua1/MAIO/releases/download/\(tag)/\(asset)"}]}
        """.utf8)
    }

    @Test func `parses version, asset and checksum`() throws {
        let release = try ReleaseInfo.parse(json())
        #expect(release.version.description == "0.1.1")
        #expect(release.assetURL.absoluteString == "https://github.com/sanhua1/MAIO/releases/download/v0.1.1/MAIO-0.1.1.zip")
        #expect(release.sha256 == "abcdef")
        #expect(release.assetSize == 3_765_100)
        #expect(release.notes.contains("修复"))
    }

    @Test func `checksum is optional`() throws {
        #expect(try ReleaseInfo.parse(json(digest: nil)).sha256 == nil)
    }

    @Test func `asset must be named after the version`() {
        #expect(throws: ReleaseInfo.ParseError.missingAsset("MAIO-0.1.1.zip")) {
            try ReleaseInfo.parse(json(asset: "MAIO-0.1.0.zip"))
        }
    }

    @Test func `prerelease and garbage are rejected`() {
        #expect(throws: ReleaseInfo.ParseError.invalidVersion("v0.1.1")) { try ReleaseInfo.parse(json(prerelease: true)) }
        #expect(throws: ReleaseInfo.ParseError.invalidJSON) { try ReleaseInfo.parse(Data("{}".utf8)) }
    }
}

struct UpdateSettingsTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func `checks when never checked or a day has passed`() {
        var settings = UpdateSettings()
        #expect(settings.isCheckDue(now: now))
        settings.lastCheck = now.addingTimeInterval(-3600)
        #expect(!settings.isCheckDue(now: now))
        settings.lastCheck = now.addingTimeInterval(-UpdateSettings.checkInterval)
        #expect(settings.isCheckDue(now: now))
        // 系统时间被往回调
        settings.lastCheck = now.addingTimeInterval(3600)
        #expect(settings.isCheckDue(now: now))
    }

    @Test func `never checks automatically when turned off`() {
        var settings = UpdateSettings()
        settings.automaticChecks = false
        #expect(!settings.isCheckDue(now: now))
    }
}

struct UpdateInstallerTests {
    @Test func `sha256 matches shasum`() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "maio-sha-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try UpdateInstaller.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func `refuses to replace a translocated app`() {
        let url = URL(filePath: "/private/var/folders/x/AppTranslocation/ABC/d/MAIO.app")
        #expect(throws: UpdateInstaller.Failure.self) { try UpdateInstaller.checkReplaceable(url) }
    }
}
