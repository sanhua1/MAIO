@testable import FeatureFinder
import Foundation
import Testing

struct ContextMenuTests {
    @Test func `config lists enabled actions with template submenu`() {
        let config = ContextMenuConfig.make(enabled: [.newFile, .copyPath, .cut], templates: ["Word 文档.docx", "文本文档.txt"])
        #expect(config.entries.map(\.id) == ["newFile", "cut", "copyPath"])
        let newFile = config.entries[0]
        #expect(newFile.children?.map(\.id) == ["template:Word 文档.docx", "template:文本文档.txt"])
        #expect(newFile.children?.map(\.title) == ["Word 文档", "文本文档"])
        #expect(config.entries[1].places == [.items])
        #expect(config.entries[2].places == [.items, .container])
    }

    @Test func `new file menu disappears without templates`() {
        let config = ContextMenuConfig.make(enabled: [.newFile, .paste], templates: [])
        #expect(config.entries.map(\.id) == ["paste"])
    }

    @Test func `config json matches what the extension decodes`() throws {
        let config = ContextMenuConfig.make(enabled: [.newFile], templates: ["a.txt"])
        let json = try #require(String(data: JSONEncoder().encode(config), encoding: .utf8))
        // 扩展（FinderSync/FinderSync.swift）按这些字段名解码
        for field in ["\"entries\"", "\"id\"", "\"title\"", "\"symbol\"", "\"places\"", "\"children\"", "\"container\""] {
            #expect(json.contains(field), "\(field)")
        }
    }

    @Test func `templates are seeded once and listed`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "maio-templates-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TemplateStore(dataDirectory: root)
        store.seedIfNeeded()
        let names = store.list()
        #expect(names.count == 5)
        #expect(names.contains("Word 文档.docx"))
        let docx = try Data(contentsOf: store.url(of: "Word 文档.docx"))
        #expect(docx.prefix(2) == Data("PK".utf8), "docx 是 zip")
        try FileManager.default.removeItem(at: store.url(of: "文本文档.txt"))
        store.seedIfNeeded()
        #expect(store.list().count == 4, "文件夹已存在时不再补默认模板（用户删掉的不会回来）")
    }

    @Test func `new file names`() {
        #expect(FileTemplates.newFileName(for: "Word 文档.docx") == "新建 Word 文档.docx")
        #expect(FileTemplates.split("archive.tar.gz") == ("archive.tar", ".gz"))
    }
}
