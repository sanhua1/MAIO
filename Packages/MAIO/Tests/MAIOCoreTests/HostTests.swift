import Foundation
@testable import MAIOCore
import MAIOKit
import MAIOTesting
import Testing

@MainActor
final class GoodFeature: Feature {
    static let manifest = FeatureManifest(
        id: "good", displayName: "Good", symbol: "star", summary: "",
        commands: [CommandDescriptor(id: "good.ping", title: "Ping")],
        defaultBindings: [DefaultBinding(id: "good.default", trigger: .hotkey(KeyChord(string: "fn+g")!), command: "good.ping")],
    )
    static var pings = 0
    init(context: any FeatureContext) {
        self.context = context
    }

    let context: any FeatureContext
    func activate() async throws {
        context.commands.register(Self.manifest.commands[0]) { _ in Self.pings += 1 }
    }

    func deactivate() async {}
}

@MainActor
final class BrokenFeature: Feature {
    static let manifest = FeatureManifest(id: "broken", displayName: "Broken", symbol: "xmark", summary: "")
    init(context _: any FeatureContext) {}
    func activate() async throws {
        throw CommandError.failed("boom")
    }

    func deactivate() async {}
}

@MainActor
final class NeedsScreenFeature: Feature {
    static let manifest = FeatureManifest(
        id: "screen", displayName: "Screen", symbol: "camera", summary: "", requiredPermissions: [.screenRecording],
    )
    init(context _: any FeatureContext) {}
    func activate() async throws {}
    func deactivate() async {}
}

@MainActor
struct HostTests {
    static func shortcuts(_ config: ConfigStore) -> FeatureShortcutDirectory.Sources {
        FeatureShortcutDirectory.Sources(
            bindings: BindingStore(config: config),
            systemShortcuts: SystemShortcutManager(store: FakeSystemShortcutStore([]), config: config),
            reservations: ShortcutReservations(), commandTitle: { $0.rawValue },
        )
    }

    private func makeRuntime(granted: Set<Permission> = Set(Permission.allCases)) -> (FeatureHost, CommandBus, ConfigStore) {
        let root = FileManager.default.temporaryDirectory.appending(path: "maio-host-\(UUID().uuidString)")
        let config = ConfigStore(root: root)
        let bus = CommandBus()
        let host = FeatureHost(
            catalog: [GoodFeature.self, BrokenFeature.self, NeedsScreenFeature.self, GoodFeature.self],
            services: .init(
                config: config, commandBus: bus, input: InputEngine { _ in },
                permissions: FakePermissions(granted: granted), overlay: RecordingOverlay(), events: FakeSystemEvents(),
                shortcuts: Self.shortcuts(config),
            ),
        )
        return (host, bus, config)
    }

    @Test func `isolates failures and permissions`() async throws {
        let (host, bus, _) = makeRuntime(granted: [.accessibility])
        await host.startAll()
        #expect(host.catalog.count == 3, "重复的功能 ID 应被丢弃")
        #expect(host.state(of: "good") == .running)
        #expect(host.state(of: "broken") == .failed("boom"))
        #expect(host.state(of: "screen") == .needsPermission([.screenRecording]))
        try await bus.perform("good.ping", source: .test)
        #expect(GoodFeature.pings > 0)
    }

    @Test func `disabling unregisters commands and persists`() async {
        let (host, bus, config) = makeRuntime()
        await host.startAll()
        await host.setEnabled(false, for: "good")
        #expect(!bus.isAvailable("good.ping"))
        #expect(host.state(of: "good") == .disabled)
        let reloaded = FeatureHost(
            catalog: [GoodFeature.self],
            services: .init(
                config: config, commandBus: bus, input: InputEngine { _ in },
                permissions: FakePermissions(), overlay: RecordingOverlay(), events: FakeSystemEvents(),
                shortcuts: Self.shortcuts(config),
            ),
        )
        #expect(!reloaded.isEnabled("good"))
    }

    @Test func `bus rejects foreign command IDs`() {
        let bus = CommandBus()
        #expect(!bus.register(CommandDescriptor(id: "other.x", title: ""), owner: "good") { _ in .null })
        #expect(bus.register(CommandDescriptor(id: "good.x", title: ""), owner: "good") { _ in .null })
        #expect(!bus.register(CommandDescriptor(id: "good.x", title: ""), owner: "bad") { _ in .null })
    }

    @Test func `lists registered commands in catalog order`() {
        let bus = CommandBus()
        bus.describeFeatures([GoodFeature.manifest, NeedsScreenFeature.manifest])
        bus.register(CommandDescriptor(id: "screen.shot", title: ""), owner: "screen") { _ in .null }
        bus.register(CommandDescriptor(id: "good.extra", title: ""), owner: "good") { _ in .null }
        bus.register(GoodFeature.manifest.commands[0], owner: "good") { _ in .null }
        let listed = bus.availableCommands()
        #expect(listed.map(\.id) == ["good.ping", "good.extra", "screen.shot"], "按目录顺序，manifest 里声明的在前")
        #expect(listed.first?.featureName == "Good")
        #expect(listed.last?.featureSymbol == "camera")
        bus.unregisterAll(owner: "good")
        #expect(bus.availableCommands().map(\.id) == ["screen.shot"])
    }
}

@MainActor
struct BindingStoreTests {
    @Test func `seeds defaults only once`() {
        let config = ConfigStore(root: FileManager.default.temporaryDirectory.appending(path: "maio-b-\(UUID().uuidString)"))
        let store = BindingStore(config: config)
        store.seed(GoodFeature.manifest.defaultBindings)
        #expect(store.bindings.count == 1)
        store.remove(id: "good.default")
        let reloaded = BindingStore(config: config)
        reloaded.seed(GoodFeature.manifest.defaultBindings)
        #expect(reloaded.bindings.isEmpty, "用户删除的出厂绑定不应被重新添加")
    }

    @Test func `detects conflicts`() throws {
        let config = ConfigStore(root: FileManager.default.temporaryDirectory.appending(path: "maio-c-\(UUID().uuidString)"))
        let store = BindingStore(config: config)
        let chord = try #require(KeyChord(string: "fn+a"))
        store.upsert(CommandBinding(id: "1", trigger: .hotkey(chord), command: "a.x"))
        let other = CommandBinding(id: "2", trigger: .hotkey(chord), command: "b.y")
        #expect(store.conflicts(with: other).map(\.id) == ["1"])
        let scoped = CommandBinding(id: "3", trigger: .hotkey(chord), command: "b.y", scope: .onlyIn(["x"]))
        store.upsert(CommandBinding(id: "4", trigger: .hotkey(chord), command: "a.x", scope: .onlyIn(["y"])))
        #expect(store.conflicts(with: scoped).map(\.id) == ["1"])
    }

    @Test func `corrupt file falls back and is quarantined`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "maio-q-\(UUID().uuidString)")
        let config = ConfigStore(root: root)
        let url = config.url(for: BindingStore.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        let store = BindingStore(config: config)
        #expect(store.bindings.isEmpty)
        #expect(config.issues.count == 1)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

struct FeatureSettingsTests {
    struct Sample: FeatureSettings {
        static let schemaVersion = 2
        static let defaultValue = Sample(speed: 1, newField: "default")
        var speed: Double
        var newField: String
        static func migrate(_ json: inout JSONValue, from version: Int) throws {
            if version < 2, case var .object(dict) = json {
                dict["speed"] = dict.removeValue(forKey: "velocity")
                json = .object(dict)
            }
        }
    }

    @Test @MainActor func `migrates and fills defaults`() throws {
        let config = ConfigStore(root: FileManager.default.temporaryDirectory.appending(path: "maio-s-\(UUID().uuidString)"))
        try config.write(["schemaVersion": 1, "value": ["velocity": 3]], to: "config/features/demo.json")
        let store = FeatureSettingsStore(featureID: "demo", config: config)
        #expect(store.load(Sample.self) == Sample(speed: 3, newField: "default"))
    }
}

@MainActor
struct ShortcutDirectoryTests {
    @Test func `features see each other's reservations but not their own`() throws {
        let config = ConfigStore(root: FileManager.default.temporaryDirectory.appending(path: "maio-dir-\(UUID().uuidString)"))
        let sources = HostTests.shortcuts(config)
        let finder = FeatureShortcutDirectory(featureID: "finder", sources: sources)
        let other = FeatureShortcutDirectory(featureID: "other", sources: sources)
        let chord = try #require(KeyChord(string: "cmd+x"))
        finder.reserve([ReservedShortcut(chord: chord, scope: .onlyIn(["com.apple.finder"]), title: "剪切")])
        #expect(finder.occupants(of: chord, scope: .global).isEmpty)
        #expect(other.occupants(of: chord, scope: .global).map(\.title) == ["剪切"])
        #expect(other.occupants(of: chord, scope: .onlyIn(["com.apple.Safari"])).isEmpty, "作用范围不重叠")
        sources.bindings.upsert(CommandBinding(id: "b", trigger: .hotkey(chord), command: "other.do"))
        #expect(finder.occupants(of: chord, scope: .onlyIn(["com.apple.finder"])).map(\.kind) == [.binding])
        finder.tearDown()
        #expect(other.occupants(of: chord, scope: .global).isEmpty, "停用后清空登记")
    }
}
