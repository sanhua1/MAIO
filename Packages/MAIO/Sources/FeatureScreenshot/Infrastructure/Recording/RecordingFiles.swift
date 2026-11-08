import AppKit
import AVFoundation

/// 录屏文件的位置、剪贴板、麦克风权限
enum RecordingFiles {
    static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies/MAIO", directoryHint: .isDirectory)
    }

    static func directory(_ setting: String) -> URL {
        setting.isEmpty ? defaultDirectory() : URL(fileURLWithPath: setting, isDirectory: true)
    }

    /// 在文件夹里按时间生成一个不重名的文件位置（文件夹不存在时创建）
    static func makeURL(in directory: URL, format: RecordingFormat, date: Date) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = RecordingFileName.make(date: date, format: format) { name in
            FileManager.default.fileExists(atPath: directory.appending(path: name).path)
        }
        return directory.appending(path: name)
    }

    /// 把文件本身放到剪贴板（可以直接粘贴到访达、微信、邮件）
    @MainActor static func copyToPasteboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }
}

/// 麦克风权限：只有打开"录麦克风"时才请求
enum MicrophoneAccess {
    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    @MainActor static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}
