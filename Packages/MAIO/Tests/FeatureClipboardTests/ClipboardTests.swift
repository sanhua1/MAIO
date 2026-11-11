import AppKit
@testable import FeatureClipboard
import Foundation
import MAIOKit
import MAIOTesting
import Testing

@MainActor
struct ClipboardTests {
    @Test func `registers declared commands`() async throws {
        let context = FakeFeatureContext(featureID: "clipboard")
        let feature = ClipboardFeature(context: context)
        try await feature.activate()
        #expect(Set(context.fakeCommands.descriptors.keys) == Set(ClipboardFeature.manifest.commands.map(\.id)))
        await feature.deactivate()
    }

    @Test func `default hotkey is control V`() {
        let binding = ClipboardFeature.manifest.defaultBindings.first
        #expect(binding?.command == ClipboardCommands.show)
        #expect(binding?.trigger == .hotkey(KeyChord(keyCode: 9, modifiers: .control)))
    }

    @Test func `thumbnail is never enlarged beyond its own size`() {
        let small = NSImage(size: CGSize(width: 8, height: 8))
        #expect(ClipRowView.displaySize(for: small) == CGSize(width: 8, height: 8))
        let wide = NSImage(size: CGSize(width: 40, height: 3))
        #expect(ClipRowView.displaySize(for: wide) == CGSize(width: 40, height: 3))
    }

    @Test func `large thumbnail shrinks to fit the row`() {
        let large = NSImage(size: CGSize(width: 400, height: 88))
        #expect(ClipRowView.displaySize(for: large) == ClipRowView.maxThumbnailSize)
        let tall = NSImage(size: CGSize(width: 120, height: 300))
        #expect(ClipRowView.displaySize(for: tall) == CGSize(width: 18, height: 44))
    }
}

func text(_ value: String) -> ClipPayload {
    ClipPayload(representations: [Representation(itemIndex: 0, type: PasteType.plainText, data: Data(value.utf8))])
}

struct ClipPayloadTests {
    @Test func `classifies kinds`() {
        #expect(text("hi").kind == .text)
        var rich = text("hi")
        rich.representations.append(Representation(itemIndex: 0, type: PasteType.html, data: Data("<b>hi</b>".utf8)))
        #expect(rich.kind == .richText)
        #expect(rich.plainTextOnly == text("hi"))
        let image = ClipPayload(representations: [Representation(itemIndex: 0, type: PasteType.png, data: Data([1]))])
        #expect(image.kind == .image)
        let files = ClipPayload(representations: [
            Representation(itemIndex: 0, type: PasteType.fileURL, data: Data("file:///tmp/a.txt".utf8)),
            Representation(itemIndex: 1, type: PasteType.fileURL, data: Data("file:///tmp/b.txt".utf8)),
        ])
        #expect(files.kind == .files)
        #expect(files.summary == "a.txt 等 2 个文件")
    }

    @Test func `summary collapses whitespace`() {
        #expect(text("  a\n\n b\tc ").summary == "a b c")
    }
}

struct RetentionPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func entry(_ id: Int64, size: Int64, age: TimeInterval, pinned: Bool = false) -> RetentionPolicy.Entry {
        .init(id: id, byteSize: size, lastUsedAt: now.addingTimeInterval(-age), isPinned: pinned)
    }

    @Test func `removes oldest until under limit`() {
        let entries = [entry(1, size: 50, age: 10), entry(2, size: 50, age: 30), entry(3, size: 50, age: 20)]
        #expect(RetentionPolicy.overLimit(entries, limit: 100) == [2])
        #expect(RetentionPolicy.overLimit(entries, limit: 60) == [2, 3])
        #expect(RetentionPolicy.overLimit(entries, limit: nil).isEmpty)
    }

    @Test func `never removes pinned`() {
        let entries = [entry(1, size: 500, age: 100, pinned: true), entry(2, size: 10, age: 1)]
        #expect(RetentionPolicy.overLimit(entries, limit: 100) == [2])
        #expect(RetentionPolicy.before(entries, date: now) == [2])
    }

    @Test func `oldest bytes`() {
        let entries = [entry(1, size: 40, age: 10), entry(2, size: 40, age: 30), entry(3, size: 40, age: 20)]
        #expect(RetentionPolicy.oldest(entries, bytes: 50) == [2, 3])
    }
}

struct PickerStateTests {
    private func item(_ id: Int64, used: TimeInterval, pinned: Bool = false) -> ClipItem {
        ClipItem(
            id: id, kind: .text, summary: "\(id)", sourceBundleID: nil, createdAt: Date(timeIntervalSince1970: Double(id)),
            lastUsedAt: Date(timeIntervalSince1970: used), byteSize: 1, isPinned: pinned,
        )
    }

    @Test func `recent first pinned last and selects first`() {
        var state = PickerState()
        state.setItems([item(1, used: 10), item(2, used: 30, pinned: true), item(3, used: 20)])
        #expect(state.items.map(\.id) == [3, 1, 2])
        #expect(state.selected?.id == 3)
        #expect(state.quickItem(slot: 1)?.id == 3)
        #expect(state.quickItem(slot: 3) == nil)
        #expect(state.quickSlot(of: state.items[2]) == nil)
    }

    @Test func `moves with wrap around`() {
        var state = PickerState()
        state.setItems([item(1, used: 10), item(2, used: 20)])
        state.move(by: -1)
        #expect(state.selected?.id == 1)
        state.move(by: 1)
        #expect(state.selected?.id == 2)
    }

    @Test func `keeps selection after reload`() {
        var state = PickerState()
        state.setItems([item(1, used: 10), item(2, used: 20)])
        state.select(1)
        state.setItems([item(1, used: 10), item(2, used: 20), item(3, used: 30)], keepSelection: true)
        #expect(state.selected?.id == 1)
    }
}
