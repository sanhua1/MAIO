import ApplicationServices
import MAIOKit
import Observation
import os

/// 输入引擎：统一管理键盘 tap 与指针 tap（见 ARCHITECTURE §5、ADR-0003）。
@MainActor
@Observable
public final class InputEngine {
    public enum Status: Equatable, Sendable {
        case stopped
        /// 等待用户授予"辅助功能"权限（期间每 2 秒检查一次）
        case waitingForPermission
        case running
    }

    public private(set) var status: Status = .stopped
    public private(set) var isPointerTapRunning = false

    @ObservationIgnored let poster = EventPoster()
    @ObservationIgnored private let keyboard: KeyboardTap
    @ObservationIgnored private let pointer = PointerTap()
    @ObservationIgnored private var permissionPoll: Task<Void, Never>?
    @ObservationIgnored private var nextFilterToken: UInt64 = 1
    @ObservationIgnored private let logger = Logger(subsystem: "app.maio", category: "input")

    /// `onBinding` 在主线程上调用。
    public init(onBinding: @escaping @MainActor (CommandBinding) -> Void) {
        keyboard = KeyboardTap { binding in
            Task { @MainActor in onBinding(binding) }
        }
    }

    public func start() {
        guard status != .running else { return }
        if AXIsProcessTrusted(), keyboard.start() {
            status = .running
            permissionPoll?.cancel()
            permissionPoll = nil
            refreshPointerTap()
        } else {
            status = .waitingForPermission
            pollForPermission()
        }
    }

    public func stop() {
        permissionPoll?.cancel()
        permissionPoll = nil
        keyboard.stop()
        pointer.stop()
        isPointerTapRunning = false
        status = .stopped
    }

    func updateBindings(_ table: HotkeyTable) {
        keyboard.update(table: table)
    }

    func updateFrontmost(_ bundleID: String?) {
        keyboard.update(frontmost: bundleID)
        pointer.update(frontmost: bundleID)
    }

    /// 开始录制快捷键：录制期间所有按键都交给 handler，不会触发任何绑定。
    public func beginRecording(_ handler: @escaping @MainActor (KeyChord) -> Void) {
        keyboard.setRecorder { chord in
            Task { @MainActor in handler(chord) }
        }
    }

    public func endRecording() {
        keyboard.setRecorder(nil)
    }

    func beginKeyboardSession() -> any KeyboardSession {
        keyboard.beginSession()
    }

    func addFilter(_ filter: any RealtimeInputFilter, stage: FilterStage) -> FilterToken {
        let token = FilterToken(rawValue: nextFilterToken)
        nextFilterToken += 1
        pointer.add(.init(token: token, stage: stage, filter: filter))
        refreshPointerTap()
        return token
    }

    func removeFilter(_ token: FilterToken) {
        pointer.remove(token)
        refreshPointerTap()
    }

    /// 只有存在过滤器时才运行指针 tap。
    private func refreshPointerTap() {
        guard status == .running else { return }
        if pointer.hasFilters, !pointer.isRunning {
            isPointerTapRunning = pointer.start()
        } else if !pointer.hasFilters, pointer.isRunning {
            pointer.stop()
            isPointerTapRunning = false
        }
    }

    private func pollForPermission() {
        guard permissionPoll == nil else { return }
        logger.info("等待辅助功能权限")
        permissionPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard AXIsProcessTrusted() else { continue }
                self?.permissionPoll = nil
                self?.start()
                return
            }
        }
    }
}
