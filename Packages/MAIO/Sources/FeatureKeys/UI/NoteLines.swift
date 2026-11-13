import SwiftUI

/// 设置页说明：一条一行，代替一整段长文字。
struct NoteLines: View {
    let lines: [String]

    init(_ lines: String...) {
        self.lines = lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// 每个标签页顶部的一句话：这一页是干什么的
struct PageIntro: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: symbol).foregroundStyle(Color.accentColor).font(.title3)
            }
            .padding(.vertical, 2)
        }
    }
}
