@testable import FeatureSwitcher
import MAIOKit
import MAIOTesting
import Testing

@MainActor
struct SwitcherFeatureTests {
    @Test func `registers commands and default opt tab bindings`() async throws {
        let context = FakeFeatureContext(featureID: "switcher")
        let feature = SwitcherFeature(context: context)
        try await feature.activate()
        #expect(Set(context.fakeCommands.descriptors.keys) == Set(SwitcherFeature.manifest.commands.map(\.id)))
        let triggers = SwitcherFeature.manifest.defaultBindings.map(\.trigger.displayString)
        #expect(triggers == ["⌥⇥", "⌥⇧⇥"])
        await feature.deactivate()
    }

    @Test func `show begins a keyboard session that ends on escape`() async throws {
        let context = FakeFeatureContext(featureID: "switcher")
        let feature = SwitcherFeature(context: context)
        try await feature.activate()
        try await context.commands.perform("switcher.show")
        #expect(context.fakeInput.sessions.count == 1)
        await feature.deactivate()
    }
}
