import Foundation

/// 当前的声音输出（CoreAudio 默认输出设备）。
struct AudioOutputInfo: Sendable, Hashable {
    var name: String
    /// 走 DisplayPort / HDMI（声音从显示器出来）
    var isDisplayTransport: Bool
    /// 系统自己能调这个设备的音量（耳机口、USB 耳机、蓝牙……）
    var canSetVolume: Bool
}

/// 能用 DDC 控制的外接显示器。
struct ControllableDisplay: Sendable, Hashable, Identifiable {
    let id: UInt32
    var name: String
    var supportsBrightness: Bool
    var supportsVolume: Bool
}

enum VolumeTargeting {
    /// 音量键该调哪台显示器。nil 表示交给系统：系统能调这个输出，或者找不到对应的显示器。
    static func display(for output: AudioOutputInfo?, among displays: [ControllableDisplay]) -> UInt32? {
        guard let output, !output.canSetVolume else { return nil }
        let candidates = displays.filter(\.supportsVolume)
        let wanted = normalized(output.name)
        if let named = candidates.first(where: { normalized($0.name) == wanted }) {
            return named.id
        }
        // 名字对不上（例如被用户改过名），但声音确实从显示器出来、又只有一台能调音量：就是它
        if output.isDisplayTransport, candidates.count == 1 {
            return candidates[0].id
        }
        return nil
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// 把 IORegistry 里的 DDC 通道对应到屏幕（CGDirectDisplayID）。
/// 思路参考：references/MonitorControl/MonitorControl/Support/Arm64DDC.swift（ioregMatchScore、getServiceMatches），
/// 这里改用公开的 CGDisplayVendorNumber / ModelNumber / SerialNumber 比对。
enum DisplayMatching {
    struct Service: Sendable, Hashable {
        let index: Int
        var vendor: Int?
        var product: Int?
        var serial: Int?
        var name: String?
    }

    struct Screen: Sendable, Hashable {
        let id: UInt32
        var vendor: Int
        var model: Int
        var serial: Int
        var name: String
    }

    /// 返回 屏幕 ID → 通道序号。分数高的先配对，每个屏幕、每个通道只用一次
    static func match(services: [Service], screens: [Screen]) -> [UInt32: Int] {
        if services.count == 1, screens.count == 1 {
            return [screens[0].id: services[0].index]
        }
        let scored = screens.flatMap { screen in
            services.map { (screen: screen.id, service: $0.index, score: score($0, screen)) }
        }
        .filter { $0.score > 0 }
        .sorted { $0.score > $1.score }
        var result: [UInt32: Int] = [:]
        var usedServices: Set<Int> = []
        for pair in scored where result[pair.screen] == nil && !usedServices.contains(pair.service) {
            result[pair.screen] = pair.service
            usedServices.insert(pair.service)
        }
        return result
    }

    static func score(_ service: Service, _ screen: Screen) -> Int {
        var score = 0
        if service.vendor == screen.vendor {
            score += 2
        }
        if service.product == screen.model {
            score += 2
        }
        if let serial = service.serial, serial != 0, serial == screen.serial {
            score += 3
        }
        if let name = service.name, !name.isEmpty, name.lowercased() == screen.name.lowercased() {
            score += 1
        }
        return score
    }
}
