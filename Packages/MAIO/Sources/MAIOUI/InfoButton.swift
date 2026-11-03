import SwiftUI

/// ⓘ 说明按钮：点击弹出说明文字。设置项不够直观时放在标题旁边。
public struct InfoButton: View {
    let title: String?
    let message: String
    @State private var isPresented = false

    public init(_ message: String, title: String? = nil) {
        self.message = message
        self.title = title
    }

    public var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(message)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title).font(.headline)
                }
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 320, alignment: .leading)
        }
    }
}

/// 标题 + ⓘ 说明，用作 Toggle / LabeledContent 的标签。
public struct LabelWithInfo: View {
    let title: String
    let info: String

    public init(_ title: String, info: String) {
        self.title = title
        self.info = info
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(title)
            InfoButton(info, title: title)
        }
    }
}
