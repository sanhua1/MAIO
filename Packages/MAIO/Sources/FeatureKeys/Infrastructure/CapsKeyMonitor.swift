import Foundation
import IOKit.hid
import Synchronization

/// Caps 键是否按住：从键盘的原始输入（IOHIDManager）里读，不受 HID 层映射影响，
/// 所以 Caps 被设成"无操作"、不产生任何按键事件时也能知道它的按下 / 松开。需要输入监控权限。
///
/// 在自己的线程上跑 run loop：主线程忙时 Caps 的状态也不会延迟。tap 线程只读 `isHeld`。
final class CapsKeyMonitor: CapsState, @unchecked Sendable {
    /// 按住 Caps 的键盘（两个键盘同时按住时，松开一个不算松开）
    private let held = Mutex<Set<UInt>>([])
    private let lock = NSLock()
    private var manager: IOHIDManager?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    var isHeld: Bool {
        held.withLock { !$0.isEmpty }
    }

    /// 返回 IOHIDManager 打开的结果（没有输入监控权限时失败）
    func start() -> IOReturn {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        IOHIDManagerSetInputValueMatching(manager, [
            kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad, kIOHIDElementUsageKey: kHIDUsage_KeyboardCapsLock,
        ] as CFDictionary)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { return result }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, sender, value in
            guard let context else { return }
            Unmanaged<CapsKeyMonitor>.fromOpaque(context).takeUnretainedValue().handle(value, sender: sender)
        }, context)
        lock.withLock { self.manager = manager }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            defer { ready.signal() }
            guard let self, let loop = CFRunLoopGetCurrent() else { return }
            let manager = lock.withLock {
                runLoop = loop
                return self.manager
            }
            guard let manager else { return }
            IOHIDManagerScheduleWithRunLoop(manager, loop, CFRunLoopMode.defaultMode.rawValue)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "MAIO Caps"
        thread.qualityOfService = QualityOfService.userInteractive
        thread.start()
        ready.wait()
        self.thread = thread
        return result
    }

    func stop() {
        guard let manager = lock.withLock({ self.manager }) else { return }
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if let loop = lock.withLock({ runLoop }) {
            IOHIDManagerUnscheduleFromRunLoop(manager, loop, CFRunLoopMode.defaultMode.rawValue)
            CFRunLoopStop(loop)
        }
        lock.withLock {
            self.manager = nil
            runLoop = nil
        }
        thread = nil
        held.withLock { $0.removeAll() }
    }

    private func handle(_ value: IOHIDValue, sender: UnsafeMutableRawPointer?) {
        let pressed = IOHIDValueGetIntegerValue(value) != 0
        let device = UInt(bitPattern: sender)
        held.withLock { set in
            if pressed {
                set.insert(device)
            } else {
                set.remove(device)
            }
        }
    }
}
