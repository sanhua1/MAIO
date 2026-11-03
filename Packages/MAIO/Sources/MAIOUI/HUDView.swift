import SwiftUI

/// 屏幕中央的短暂提示。
public struct HUDView: View {
    public enum Style: Sendable { case info, error }

    let message: String
    let symbol: String?
    let style: Style

    public init(message: String, symbol: String? = nil, style: Style = .info) {
        self.message = message
        self.symbol = symbol
        self.style = style
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let icon = symbol ?? (style == .error ? "exclamationmark.triangle.fill" : nil) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(style == .error ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            }
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(12)
    }
}
