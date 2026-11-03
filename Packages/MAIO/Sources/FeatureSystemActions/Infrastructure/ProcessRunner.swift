import Foundation
import Synchronization

/// 在后台运行子进程，不阻塞主线程；功能停用时终止所有仍在运行的进程。
final class ProcessRunner: Sendable {
    private let running = Mutex<[ObjectIdentifier: Process]>([:])
    /// 超过这个时间仍未结束的进程会被终止
    let timeout: Duration = .seconds(60)

    func run(_ job: ProcessJob) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(filePath: job.executable)
        process.arguments = job.arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        let id = ObjectIdentifier(process)

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] finished in
                self?.running.withLock { _ = $0.removeValue(forKey: id) }
                let result = ProcessResult(
                    exitCode: finished.terminationStatus,
                    output: Self.read(output),
                    error: Self.read(error),
                )
                continuation.resume(returning: result)
            }
            do {
                try process.run()
                running.withLock { $0[id] = process }
                scheduleTimeout(for: process)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func cancelAll() async {
        let processes = running.withLock { dict in
            defer { dict.removeAll() }
            return Array(dict.values)
        }
        processes.forEach { $0.terminate() }
    }

    private func scheduleTimeout(for process: Process) {
        let timeout = timeout
        Task.detached {
            try? await Task.sleep(for: timeout)
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private static func read(_ pipe: Pipe) -> String {
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
