@testable import FeatureTranslate
import MAIOKit
import MAIOTesting
import Testing

@MainActor
struct TranslateTests {
    @Test func `registers declared commands`() async throws {
        let context = FakeFeatureContext(featureID: "translate")
        try await TranslateFeature(context: context).activate()
        #expect(Set(context.fakeCommands.descriptors.keys) == Set(TranslateFeature.manifest.commands.map(\.id)))
    }

    @Test func `default hotkey is option Q`() {
        let binding = TranslateFeature.manifest.defaultBindings.first
        #expect(binding?.command == TranslateCommands.show)
        #expect(binding?.trigger == .hotkey(KeyChord(keyCode: 12, modifiers: .option)))
    }

    @Test func `missing key is reported on card`() async {
        let context = FakeFeatureContext(featureID: "translate")
        let factory = ProviderFactory(secrets: context.secrets)
        let provider = factory.make(.make(kind: .baidu, id: "b"))
        let request = TranslationRequest(text: "hi", source: .english, target: .simplifiedChinese)
        await #expect(throws: TranslationError.missingSecret("APP ID")) {
            try await provider.translate(request) { _ in }
        }
    }
}
