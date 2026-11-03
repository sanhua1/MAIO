@testable import FeatureScreenshot
import MAIOKit
import MAIOTesting
import Testing

@MainActor
struct ScreenshotTests {
    @Test func `registers declared commands`() async throws {
        let context = FakeFeatureContext(featureID: "screenshot")
        let feature = ScreenshotFeature(context: context)
        try await feature.activate()
        #expect(Set(context.fakeCommands.descriptors.keys) == Set(ScreenshotFeature.manifest.commands.map(\.id)))
        await feature.deactivate()
    }

    @Test func `default hotkey is option F1`() {
        let binding = ScreenshotFeature.manifest.defaultBindings.first
        #expect(binding?.command == ScreenshotCommands.capture)
        #expect(binding?.trigger == .hotkey(KeyChord(keyCode: 122, modifiers: .option)))
    }
}
