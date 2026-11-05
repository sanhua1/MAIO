import Foundation

/// 新建文件的模板文件夹（`data/finder/templates/`）。用户可以往里面放任何空白文件（例如自己的 Word 模板），
/// 右键菜单「新建」里就会多一项。第一次使用时放入几个默认模板。
struct TemplateStore {
    let directory: URL

    init(dataDirectory: URL) {
        directory = dataDirectory.appending(path: "templates", directoryHint: .isDirectory)
    }

    /// 模板文件名，按名称排序（不含隐藏文件）
    func list() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func url(of name: String) -> URL {
        directory.appending(path: name)
    }

    /// 模板文件夹不存在时创建，并放入默认模板
    func seedIfNeeded() {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in Self.plainTemplates {
            try? data.write(to: url(of: name))
        }
        for (name, parts) in OfficeTemplates.all {
            try? OfficeTemplates.write(parts, to: url(of: name))
        }
    }

    static let plainTemplates: [(String, Data)] = [
        ("文本文档.txt", Data()),
        ("Markdown 文档.md", Data()),
        ("RTF 文档.rtf", Data("{\\rtf1\\ansi\\deff0 }".utf8)),
    ]
}

/// 最小的空白 Word / Excel 文件（Office Open XML：几段 XML 打成 zip）
enum OfficeTemplates {
    private static let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
    private static let relationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let packageRelationships = "http://schemas.openxmlformats.org/package/2006/relationships"
    private static let contentTypes = "http://schemas.openxmlformats.org/package/2006/content-types"

    static let all: [(String, [(path: String, xml: String)])] = [("Word 文档.docx", word), ("Excel 工作表.xlsx", excel)]

    static let word: [(path: String, xml: String)] = [
        (
            "[Content_Types].xml",
            header + #"<Types xmlns="\#(contentTypes)"><Default Extension="rels" "#
                + #"ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" "#
                + #"ContentType="application/xml"/><Override PartName="/word/document.xml" "#
                + #"ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>"#,
        ),
        (
            "_rels/.rels",
            header + #"<Relationships xmlns="\#(packageRelationships)"><Relationship Id="rId1" "#
                + #"Type="\#(relationships)/officeDocument" Target="word/document.xml"/></Relationships>"#,
        ),
        (
            "word/document.xml",
            header + #"<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">"#
                + "<w:body><w:p/></w:body></w:document>",
        ),
    ]

    static let excel: [(path: String, xml: String)] = [
        (
            "[Content_Types].xml",
            header + #"<Types xmlns="\#(contentTypes)"><Default Extension="rels" "#
                + #"ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" "#
                + #"ContentType="application/xml"/><Override PartName="/xl/workbook.xml" "#
                + #"ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>"#
                + #"<Override PartName="/xl/worksheets/sheet1.xml" "#
                + #"ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>"#,
        ),
        (
            "_rels/.rels",
            header + #"<Relationships xmlns="\#(packageRelationships)"><Relationship Id="rId1" "#
                + #"Type="\#(relationships)/officeDocument" Target="xl/workbook.xml"/></Relationships>"#,
        ),
        (
            "xl/workbook.xml",
            header + #"<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" "#
                + #"xmlns:r="\#(relationships)"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>"#,
        ),
        (
            "xl/_rels/workbook.xml.rels",
            header + #"<Relationships xmlns="\#(packageRelationships)"><Relationship Id="rId1" "#
                + #"Type="\#(relationships)/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#,
        ),
        (
            "xl/worksheets/sheet1.xml",
            header
                + #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>"#,
        ),
    ]

    /// 把各部分写进临时目录，用系统自带的 zip 打包
    static func write(_ parts: [(path: String, xml: String)], to destination: URL) throws {
        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appending(
            path: "maio-template-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        defer { try? manager.removeItem(at: staging) }
        for part in parts {
            let file = staging.appending(path: part.path)
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(part.xml.utf8).write(to: file)
        }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/zip")
        process.currentDirectoryURL = staging
        process.arguments = ["-X", "-q", "-r", destination.path(percentEncoded: false)] + parts.map(\.path)
        try process.run()
        process.waitUntilExit()
    }
}
