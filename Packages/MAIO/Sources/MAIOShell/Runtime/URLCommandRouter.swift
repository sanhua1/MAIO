import Foundation
import MAIOKit

/// URL Scheme 触发器：`maio://run/<commandID>?参数=值`
/// 例：`open "maio://run/system.openApp?app=com.apple.Safari"`
enum URLCommandRouter {
    static func parse(_ url: URL) -> (CommandID, CommandArguments)? {
        guard url.scheme == "maio", url.host() == "run",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let id = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard id.contains(".") else { return nil }
        var arguments: CommandArguments = [:]
        for item in components.queryItems ?? [] {
            arguments[item.name] = value(from: item.value ?? "")
        }
        return (CommandID(rawValue: id), arguments)
    }

    private static func value(from raw: String) -> JSONValue {
        switch raw {
        case "true": .bool(true)
        case "false": .bool(false)
        default: .string(raw)
        }
    }
}
