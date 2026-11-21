import AppKit
import CoreGraphics
import IOKit

/// 一台找到了 DDC 通道的外接显示器（还不知道支持哪些功能码）。
struct ScannedDisplay {
    let id: CGDirectDisplayID
    let name: String
    let channel: DDCChannel
}

/// 找出所有外接显示器和它们的 DDC 通道。
/// 遍历方式参考：references/MonitorControl/MonitorControl/Support/Arm64DDC.swift（getIoregServicesForMatching）：
/// IORegistry 里每个帧缓冲（AppleCLCD2 / IOMobileFramebufferShim）后面跟着它的 DCPAVServiceProxy。
@MainActor
enum DisplayScanner {
    private struct FoundService {
        let info: DisplayMatching.Service
        let channel: DDCChannel
    }

    static func scan() -> [ScannedDisplay] {
        let screens = externalScreens()
        guard !screens.isEmpty else { return [] }
        let services = externalServices()
        let matches = DisplayMatching.match(services: services.map(\.info), screens: screens)
        return screens.compactMap { screen in
            guard let index = matches[screen.id], let found = services.first(where: { $0.info.index == index }) else {
                return nil
            }
            let name = screen.name.isEmpty ? (found.info.name ?? "外接显示器") : screen.name
            return ScannedDisplay(id: screen.id, name: name, channel: found.channel)
        }
    }

    private static func externalScreens() -> [DisplayMatching.Screen] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        // 用 online 而不是 active：显示器睡眠时不算 active，但 DDC 照样能用（唤醒前就把状态读好）
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        let names = Dictionary(
            NSScreen.screens.compactMap { screen in screen.displayID.map { ($0, screen.localizedName) } },
            uniquingKeysWith: { first, _ in first },
        )
        return ids.prefix(Int(count))
            // 镜像时只控制主体那一台（被镜像的屏幕 CGDisplayMirrorsDisplay 不为 0）
            .filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { id in
                DisplayMatching.Screen(
                    id: id,
                    vendor: Int(CGDisplayVendorNumber(id)),
                    model: Int(CGDisplayModelNumber(id)),
                    serial: Int(CGDisplaySerialNumber(id)),
                    name: names[id] ?? "",
                )
            }
    }

    private static func externalServices() -> [FoundService] {
        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator)
            == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [FoundService] = []
        var lastFramebuffer = DisplayMatching.Service(index: 0)
        var name = [CChar](repeating: 0, count: 128)
        while case let entry = IOIteratorNext(iterator), entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { continue }
            let entryName = name.withUnsafeBufferPointer { buffer in
                buffer.baseAddress.map { String(cString: $0) } ?? ""
            }
            if entryName == "AppleCLCD2" || entryName == "IOMobileFramebufferShim" {
                lastFramebuffer = framebufferInfo(entry, index: result.count)
            } else if entryName == "DCPAVServiceProxy", string(entry, "Location") == "External",
                      let channel = DDCChannel(entry: entry) {
                result.append(FoundService(info: lastFramebuffer, channel: channel))
                lastFramebuffer = DisplayMatching.Service(index: result.count)
            }
        }
        return result
    }

    private static func framebufferInfo(_ entry: io_registry_entry_t, index: Int) -> DisplayMatching.Service {
        let attributes = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        let product = attributes?["ProductAttributes"] as? [String: Any]
        return DisplayMatching.Service(
            index: index,
            vendor: product?["LegacyManufacturerID"] as? Int,
            product: product?["ProductID"] as? Int,
            serial: product?["SerialNumber"] as? Int,
            name: product?["ProductName"] as? String,
        )
    }

    private static func string(_ entry: io_registry_entry_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
