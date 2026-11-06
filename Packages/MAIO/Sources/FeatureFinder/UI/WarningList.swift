import SwiftUI

/// 冲突提示列表（红色：不会生效；橙色：会覆盖别的；灰色：说明）
struct WarningList: View {
    let warnings: [ShortcutWarning]

    var body: some View {
        ForEach(warnings) { warning in
            Label(warning.text, systemImage: symbol(warning.level))
                .font(.caption)
                .foregroundStyle(color(warning.level))
        }
    }

    private func symbol(_ level: ShortcutWarning.Level) -> String {
        switch level {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private func color(_ level: ShortcutWarning.Level) -> Color {
        switch level {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}
