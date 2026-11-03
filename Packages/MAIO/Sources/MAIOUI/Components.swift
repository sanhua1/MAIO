import MAIOKit
import SwiftUI

/// 以键帽样式显示快捷键。
public struct KeyChordLabel: View {
    let text: String

    public init(_ chord: KeyChord) {
        text = chord.displayString
    }

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary, in: .rect(cornerRadius: 5))
    }
}

/// 状态徽标（运行中 / 已停用 / 失败 …）。
public struct StatusBadge: View {
    public enum Tone: Sendable { case positive, neutral, warning, negative }

    let text: String
    let tone: Tone

    public init(_ text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Label(text, systemImage: "circle.fill")
            .labelStyle(BadgeLabelStyle(color: color))
            .font(.caption)
    }

    private var color: Color {
        switch tone {
        case .positive: .green
        case .neutral: .secondary
        case .warning: .orange
        case .negative: .red
        }
    }
}

private struct BadgeLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(color).imageScale(.small)
            configuration.title.foregroundStyle(.secondary)
        }
    }
}
