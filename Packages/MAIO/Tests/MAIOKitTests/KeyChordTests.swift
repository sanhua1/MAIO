import Foundation
import MAIOKit
import Testing

struct KeyChordTests {
    @Test(arguments: ["fn+a", "cmd+shift+4", "opt+tab", "ctrl+opt+cmd+left", "f13", "fn+key200"])
    func `round trip`(_ raw: String) throws {
        let chord = try #require(KeyChord(string: raw))
        #expect(chord.string == raw)
    }

    @Test func `parsing is order and case insensitive`() {
        #expect(KeyChord(string: "Shift+CMD+4") == KeyChord(string: "cmd+shift+4"))
        #expect(KeyChord(string: "alt+Tab") == KeyChord(string: "opt+tab"))
        #expect(KeyChord(string: "⌘+⇧+4") == KeyChord(string: "cmd+shift+4"))
    }

    @Test(arguments: ["", "cmd+", "hyper+a", "cmd+notakey"])
    func `rejects invalid`(_ raw: String) {
        #expect(KeyChord(string: raw) == nil)
    }

    @Test func `display string`() throws {
        #expect(try #require(KeyChord(string: "cmd+shift+4")).displayString == "⇧⌘4")
        #expect(try #require(KeyChord(string: "fn+a")).displayString == "fn A")
    }

    @Test func `binding JSON round trip`() throws {
        let json = """
        {"id":"x","trigger":{"hotkey":"fn+a"},"command":"system.openApp",
         "arguments":{"app":"com.apple.ActivityMonitor"},"scope":{"except":["com.apple.Terminal"]}}
        """
        let binding = try JSONDecoder().decode(CommandBinding.self, from: Data(json.utf8))
        #expect(binding.isEnabled)
        #expect(binding.scope == .exceptIn(["com.apple.Terminal"]))
        let again = try JSONDecoder().decode(CommandBinding.self, from: JSONEncoder().encode(binding))
        #expect(again == binding)
    }

    @Test func `scope applies`() {
        #expect(BindingScope.global.applies(to: nil))
        #expect(BindingScope.onlyIn(["a"]).applies(to: "a"))
        #expect(!BindingScope.onlyIn(["a"]).applies(to: "b"))
        #expect(!BindingScope.exceptIn(["a"]).applies(to: "a"))
        #expect(BindingScope.exceptIn(["a"]).applies(to: nil))
    }

    @Test func `command ID feature prefix`() {
        #expect(CommandID("screenshot.captureRegion").featureID == "screenshot")
    }
}

struct JSONValueTests {
    @Test func `merge fills missing fields`() {
        let stored: JSONValue = ["a": 1, "nested": ["x": true]]
        let defaults: JSONValue = ["a": 0, "b": "new", "nested": ["x": false, "y": 2]]
        #expect(stored.merged(over: defaults) == ["a": 1, "b": "new", "nested": ["x": true, "y": 2]])
    }
}
