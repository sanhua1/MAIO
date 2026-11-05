import Foundation

/// 常用度存在 `data/launcher/usage.json`。文件很小（最多几百条），每次打开条目后整份写回。
struct UsageStore {
    let file: URL

    init(dataDirectory: URL) {
        file = dataDirectory.appending(path: "usage.json")
    }

    func load() -> UsageBook {
        guard let data = try? Data(contentsOf: file),
              let book = try? JSONDecoder.usage.decode(UsageBook.self, from: data)
        else { return UsageBook() }
        return book
    }

    func save(_ book: UsageBook) throws {
        let data = try JSONEncoder.usage.encode(book)
        try data.write(to: file, options: .atomic)
    }
}

private extension JSONDecoder {
    static var usage: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

private extension JSONEncoder {
    static var usage: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}
