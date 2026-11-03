@testable import FeatureSystemActions
import MAIOKit
import MAIOTesting
import Testing

@MainActor
struct SystemActionsTests {
    @Test func `registers all declared commands`() async throws {
        let context = FakeFeatureContext(featureID: "system")
        let feature = SystemActionsFeature(context: context)
        try await feature.activate()
        let declared = Set(SystemActionsFeature.manifest.commands.map(\.id))
        #expect(Set(context.fakeCommands.descriptors.keys) == declared)
    }

    @Test func `send keys posts key stroke`() async throws {
        let context = FakeFeatureContext(featureID: "system")
        try await SystemActionsFeature(context: context).activate()
        try await context.commands.perform("system.sendKeys", arguments: ["keys": "cmd+shift+4"])
        let expected = try #require(KeyChord(string: "cmd+shift+4"))
        #expect(context.fakeInput.recordingPoster.events == [.keyStroke(expected)])
    }

    @Test func `send keys rejects garbage`() async throws {
        let context = FakeFeatureContext(featureID: "system")
        try await SystemActionsFeature(context: context).activate()
        await #expect(throws: CommandError.self) {
            try await context.commands.perform("system.sendKeys", arguments: ["keys": "cmd+nope"])
        }
    }

    @Test func `run shell reports failure`() async throws {
        let context = FakeFeatureContext(featureID: "system")
        try await SystemActionsFeature(context: context).activate()
        await #expect(throws: CommandError.self) {
            try await context.commands.perform("system.runShell", arguments: ["script": "echo boom >&2; exit 3"])
        }
    }

    @Test func `app target parsing`() throws {
        #expect(try AppTarget("com.apple.Safari") == .bundleID("com.apple.Safari"))
        #expect(try AppTarget("/Applications/Safari.app") == .path("/Applications/Safari.app"))
        #expect(throws: TargetError.empty) { try AppTarget("  ") }
    }

    @Test func `url target resolution`() {
        #expect(URLTarget.resolve("https://apple.com")?.absoluteString == "https://apple.com")
        #expect(URLTarget.resolve("apple.com")?.absoluteString == "https://apple.com")
        #expect(URLTarget.resolve("/tmp")?.path == "/tmp")
        #expect(URLTarget.resolve("") == nil)
    }
}
