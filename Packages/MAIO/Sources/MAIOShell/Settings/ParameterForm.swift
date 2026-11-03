import AppKit
import MAIOKit
import SwiftUI

/// 根据命令声明的 ParameterSpec 自动生成参数表单。
struct ParameterForm: View {
    let parameters: [ParameterSpec]
    @SwiftUI.Binding var arguments: CommandArguments

    var body: some View {
        ForEach(parameters) { spec in
            field(for: spec)
        }
    }

    @ViewBuilder
    private func field(for spec: ParameterSpec) -> some View {
        switch spec.kind {
        case .bool:
            Toggle(spec.title, isOn: boolBinding(spec))
        case .multilineText:
            VStack(alignment: .leading) {
                Text(spec.title)
                TextEditor(text: textBinding(spec))
                    .font(.body.monospaced())
                    .frame(minHeight: 80)
            }
        case .number:
            TextField(spec.title, value: numberBinding(spec), format: .number)
        case let .choice(options):
            Picker(spec.title, selection: textBinding(spec)) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        case .application:
            HStack {
                TextField(spec.title, text: textBinding(spec), prompt: spec.placeholder.map { Text($0) })
                if let url = BindingPresentation.applicationURL(textBinding(spec).wrappedValue) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 22, height: 22)
                        .help(url.path)
                }
                Button("选择…") { chooseApplication(for: spec) }
            }
        case .text, .keyChord:
            TextField(spec.title, text: textBinding(spec), prompt: spec.placeholder.map { Text($0) })
        }
    }

    private func textBinding(_ spec: ParameterSpec) -> SwiftUI.Binding<String> {
        SwiftUI.Binding(
            get: { arguments[spec.key]?.stringValue ?? spec.defaultValue?.stringValue ?? "" },
            set: { arguments[spec.key] = .string($0) },
        )
    }

    private func boolBinding(_ spec: ParameterSpec) -> SwiftUI.Binding<Bool> {
        SwiftUI.Binding(
            get: { arguments[spec.key]?.boolValue ?? spec.defaultValue?.boolValue ?? false },
            set: { arguments[spec.key] = .bool($0) },
        )
    }

    private func numberBinding(_ spec: ParameterSpec) -> SwiftUI.Binding<Double> {
        SwiftUI.Binding(
            get: { arguments[spec.key]?.numberValue ?? spec.defaultValue?.numberValue ?? 0 },
            set: { arguments[spec.key] = .number($0) },
        )
    }

    private func chooseApplication(for spec: ParameterSpec) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let value = Bundle(url: url)?.bundleIdentifier ?? url.path
        arguments[spec.key] = .string(value)
    }
}
