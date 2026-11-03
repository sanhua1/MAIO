import CoreFoundation
import Foundation
import MAIOKit
import os

/// 读写系统快捷键的底层接口（测试中用假实现替换）。
@MainActor
public protocol SystemShortcutStore: AnyObject {
    /// 私有 API 不可用（未来系统移除）时为 false，此时冲突检测与禁用功能整体降级为不可用。
    var isAvailable: Bool { get }
    /// 所有已分配按键的系统快捷键；启用状态以偏好设置为准。
    func readAll() -> [RawSystemShortcut]
    /// com.apple.symbolichotkeys 中该编号的原始条目（不存在则为 nil，表示使用系统默认值）。
    func preferenceEntry(for id: Int) -> JSONValue?
    /// 写入条目（nil 表示删除，恢复系统默认）并立即通知 WindowServer。
    func apply(id: Int, enabled: Bool, entry: JSONValue?)
}

/// 真实实现：SkyLight 私有函数（运行时状态）+ CFPreferences（持久化）。
/// 两者都要改：只改偏好设置要重新登录才生效；只改运行时状态重启后会丢失。
@MainActor
public final class MacSystemShortcutStore: SystemShortcutStore {
    private typealias GetValue = @convention(c) (
        Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>,
    ) -> Int32
    private typealias IsEnabled = @convention(c) (Int32) -> Bool
    private typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32

    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString
    /// 目前系统使用的编号都小于 300，留出余量
    private static let maxID: Int32 = 512

    private let getValue: GetValue?
    private let isEnabledFn: IsEnabled?
    private let setEnabledFn: SetEnabled?
    private let logger = Logger(subsystem: "app.maio", category: "system-shortcuts")

    public init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        func load<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        getValue = load("CGSGetSymbolicHotKeyValue", as: GetValue.self)
        isEnabledFn = load("CGSIsSymbolicHotKeyEnabled", as: IsEnabled.self)
        setEnabledFn = load("CGSSetSymbolicHotKeyEnabled", as: SetEnabled.self)
        if !isAvailable {
            logger.error("SkyLight 系统快捷键函数不可用，冲突检测已停用")
        }
    }

    public var isAvailable: Bool {
        getValue != nil && isEnabledFn != nil && setEnabledFn != nil
    }

    public func readAll() -> [RawSystemShortcut] {
        guard let getValue, let isEnabledFn else { return [] }
        let preferences = readPreferences()
        var result: [RawSystemShortcut] = []
        for id in 0 ..< Self.maxID {
            var character: UInt16 = 0
            var keyCode: UInt16 = 0
            var mask: UInt32 = 0
            guard getValue(id, &character, &keyCode, &mask) == 0, keyCode != 0xFFFF else { continue }
            // 运行时查询在本进程内可能是旧值（见 ADR-0005），以偏好设置为准
            let stored = preferences[String(id)]?.objectValue?["enabled"]?.boolValue
            result.append(RawSystemShortcut(
                id: Int(id), character: character, keyCode: keyCode, modifierMask: mask,
                isEnabled: stored ?? isEnabledFn(id),
            ))
        }
        return result
    }

    public func preferenceEntry(for id: Int) -> JSONValue? {
        readPreferences()[String(id)]
    }

    public func apply(id: Int, enabled: Bool, entry: JSONValue?) {
        var dictionary = (CFPreferencesCopyAppValue(Self.key, Self.domain) as? [String: Any]) ?? [:]
        dictionary[String(id)] = entry.map(PlistBridge.plist(from:))
        CFPreferencesSetAppValue(Self.key, dictionary as CFDictionary, Self.domain)
        CFPreferencesAppSynchronize(Self.domain)
        let status = setEnabledFn?(Int32(id), enabled) ?? -1
        logger.notice("系统快捷键 #\(id) → \(enabled ? "启用" : "禁用", privacy: .public)（CGS 返回 \(status)）")
    }

    private func readPreferences() -> [String: JSONValue] {
        CFPreferencesAppSynchronize(Self.domain)
        guard let raw = CFPreferencesCopyAppValue(Self.key, Self.domain) else { return [:] }
        return PlistBridge.json(from: raw)?.objectValue ?? [:]
    }
}

/// 属性列表值与 JSONValue 互转。整数必须写回整数，否则 WindowServer 无法解析。
enum PlistBridge {
    static func json(from value: Any) -> JSONValue? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                .bool(number.boolValue)
            } else {
                .number(number.doubleValue)
            }
        case let string as String: .string(string)
        case let array as [Any]: .array(array.compactMap(json(from:)))
        case let dictionary as [String: Any]: .object(dictionary.compactMapValues(json(from:)))
        default: nil
        }
    }

    static func plist(from value: JSONValue) -> Any {
        switch value {
        case .null: NSNull()
        case let .bool(flag): flag
        case let .number(number):
            number.rounded() == number && abs(number) < 1e15 ? Int(number) as Any : number as Any
        case let .string(string): string
        case let .array(array): array.map(plist(from:))
        case let .object(object): object.mapValues(plist(from:))
        }
    }
}
