import CoreGraphics
import Foundation
import os

/// 在独立线程上运行一个 CGEventTap。**全项目只有 `MAIOCore/Input/` 能创建 event tap。**
final class EventTapRunner: @unchecked Sendable {
    typealias Handler = @Sendable (CGEventType, CGEvent) -> Unmanaged<CGEvent>?

    let name: String
    let handler: Handler
    private let mask: CGEventMask
    private let location: CGEventTapLocation
    private let placement: CGEventTapPlacement
    private let lock = NSLock()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private let logger = Logger(subsystem: "app.maio", category: "input")

    init(
        name: String,
        mask: CGEventMask,
        location: CGEventTapLocation = .cghidEventTap,
        placement: CGEventTapPlacement = .headInsertEventTap,
        handler: @escaping Handler,
    ) {
        self.name = name
        self.mask = mask
        self.location = location
        self.placement = placement
        self.handler = handler
    }

    var isRunning: Bool {
        lock.withLock { port != nil }
    }

    /// 创建并启动 tap。没有辅助功能权限时返回 false。
    func start() -> Bool {
        if isRunning {
            return true
        }
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: location,
            place: placement,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: info,
        ) else {
            logger.error("\(self.name, privacy: .public) tap 创建失败（可能缺少辅助功能权限）")
            return false
        }
        nonisolated(unsafe) let unsafePort = port
        nonisolated(unsafe) let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        lock.withLock { self.port = port }
        let thread = Thread { [weak self] in
            let current = CFRunLoopGetCurrent()
            CFRunLoopAddSource(current, source, .commonModes)
            self?.lock.withLock { self?.runLoop = current }
            CGEvent.tapEnable(tap: unsafePort, enable: true)
            CFRunLoopRun()
        }
        thread.name = "app.maio.input.\(name)"
        thread.qualityOfService = .userInteractive
        thread.start()
        logger.info("\(self.name, privacy: .public) tap 已启动")
        return true
    }

    func stop() {
        let (port, runLoop) = lock.withLock {
            defer { self.port = nil; self.runLoop = nil }
            return (self.port, self.runLoop)
        }
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        logger.info("\(self.name, privacy: .public) tap 已停止")
    }

    /// 系统因超时或用户输入禁用 tap 时重新启用（tap 自愈）。
    fileprivate func reenable(reason: CGEventType) {
        logger.warning("\(self.name, privacy: .public) tap 被系统禁用（\(reason.rawValue)），重新启用")
        lock.withLock {
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
        }
    }

    deinit { stop() }
}

private func eventTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?,
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let runner = Unmanaged<EventTapRunner>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        runner.reenable(reason: type)
        return Unmanaged.passUnretained(event)
    }
    return runner.handler(type, event)
}
