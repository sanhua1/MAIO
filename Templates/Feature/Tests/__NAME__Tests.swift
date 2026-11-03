@testable import Feature__NAME__
import MAIOKit
import MAIOTesting
import Testing

@MainActor
struct __NAME__Tests {
    @Test func registersDeclaredCommands() async throws {
        let context = FakeFeatureContext(featureID: "__ID__")
        try await __NAME__Feature(context: context).activate()
        #expect(Set(context.fakeCommands.descriptors.keys) == Set(__NAME__Feature.manifest.commands.map(\.id)))
    }
}
