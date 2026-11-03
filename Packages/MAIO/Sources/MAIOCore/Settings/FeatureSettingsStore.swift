import MAIOKit

/// 单个功能的设置存储，文件为 config/features/<featureID>.json：
/// `{ "schemaVersion": n, "value": { ... } }`
@MainActor
final class FeatureSettingsStore: SettingsService {
    private let featureID: FeatureID
    private let config: ConfigStore
    private var cache: [ObjectIdentifier: any Sendable] = [:]
    private var observers: [ObjectIdentifier: [UInt64: (any Sendable) -> Void]] = [:]
    private var nextObserver: UInt64 = 0

    init(featureID: FeatureID, config: ConfigStore) {
        self.featureID = featureID
        self.config = config
    }

    private var path: String {
        "config/features/\(featureID.rawValue).json"
    }

    func load<S: FeatureSettings>(_: S.Type) -> S {
        let key = ObjectIdentifier(S.self)
        if let cached = cache[key] as? S {
            return cached
        }
        let value = decode(S.self)
        cache[key] = value
        return value
    }

    func save<S: FeatureSettings>(_ value: S) {
        let key = ObjectIdentifier(S.self)
        if let cached = cache[key] as? S, cached == value {
            return
        }
        cache[key] = value
        do {
            let file: JSONValue = try ["schemaVersion": .number(Double(S.schemaVersion)), "value": JSONValue(encoding: value)]
            try config.write(file, to: path)
        } catch {
            config.report("保存 \(featureID) 设置失败：\(error.localizedDescription)")
        }
        observers[key]?.values.forEach { $0(value) }
    }

    func changes<S: FeatureSettings>(_: S.Type) -> AsyncStream<S> {
        let key = ObjectIdentifier(S.self)
        let (stream, continuation) = AsyncStream.makeStream(of: S.self, bufferingPolicy: .bufferingNewest(1))
        let token = nextObserver
        nextObserver += 1
        observers[key, default: [:]][token] = { value in
            if let value = value as? S {
                continuation.yield(value)
            }
        }
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.observers[key]?[token] = nil }
        }
        return stream
    }

    private func decode<S: FeatureSettings>(_: S.Type) -> S {
        guard let file = config.read(path)?.objectValue, var value = file["value"] else { return S.defaultValue }
        let version = file["schemaVersion"]?.numberValue.map { Int($0) } ?? 1
        do {
            if version < S.schemaVersion {
                try S.migrate(&value, from: version)
            }
            return try value.merged(over: JSONValue(encoding: S.defaultValue)).decode(S.self)
        } catch {
            config.report("\(featureID) 设置无法读取（\(error)），改用默认值。")
            return S.defaultValue
        }
    }
}
