import AppKit
import MAIOKit
import SwiftUI

/// 单个翻译源的配置表单：按 spec 自动生成，密钥写入钥匙串；可以一键测试。
struct ServiceEditorView: View {
    @SwiftUI.Binding var service: ServiceConfig
    let secrets: any SecretService
    let factory: ProviderFactory
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle
        case running
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(service.spec.summary).font(.caption).foregroundStyle(.secondary)
            TextField("显示名称", text: $service.name)
            ForEach(service.spec.fields) { field in
                FieldEditor(field: field, service: $service, secrets: secrets)
            }
            HStack {
                Button("测试") { Task { await test() } }
                    .disabled(testState == .running)
                if let signup = signupURL {
                    Link("申请 Key", destination: signup).font(.callout)
                }
                Spacer()
            }
            testResult
        }
        .padding(.vertical, 4)
    }

    private var signupURL: URL? {
        if service.kind == .openAICompatible {
            let preset = LLMPreset.all.first { $0.baseURL == service.option("baseURL") }
            return preset.flatMap { URL(string: $0.signupURL) }
        }
        return service.spec.signupURL.flatMap(URL.init(string:))
    }

    @ViewBuilder private var testResult: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case let .success(text):
            Label("可以使用：hello → \(text)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
        case let .failure(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red).font(.callout).textSelection(.enabled)
        }
    }

    private func test() async {
        testState = .running
        let provider = factory.make(service)
        let request = TranslationRequest(text: "hello", source: .english, target: .simplifiedChinese, detected: .english)
        do {
            let result = try await provider.translate(request) { _ in }
            testState = .success(result.text)
        } catch {
            testState = .failure((error as? TranslationError)?.message ?? TranslateViewModel.describe(error))
        }
    }
}

/// 一个配置项。密钥字段用 SecureField，停止输入 0.5 秒后写入钥匙串。
private struct FieldEditor: View {
    let field: ProviderField
    @SwiftUI.Binding var service: ServiceConfig
    let secrets: any SecretService
    @State private var secret = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var error: String?

    var body: some View {
        switch field.kind {
        case .text:
            TextField(field.title, text: option, prompt: Text(placeholder))
        case .secret:
            VStack(alignment: .leading, spacing: 2) {
                SecureField(field.title, text: $secret, prompt: Text("保存在钥匙串中"))
                    .onAppear { secret = secrets.secret(for: service.secretKey(field.key)) ?? "" }
                    .onChange(of: secret) { _, newValue in scheduleSave(newValue) }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        case .multiline:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(field.title).font(.callout)
                    Spacer()
                    Button("恢复默认") { service.options[field.key] = nil }
                        .controlSize(.small)
                }
                TextEditor(text: multilineOption)
                    .font(.callout.monospaced())
                    .frame(minHeight: 60, maxHeight: 120)
                    .border(.separator)
            }
        }
    }

    private var placeholder: String {
        field.placeholder.isEmpty ? field.defaultValue : field.placeholder
    }

    private var option: SwiftUI.Binding<String> {
        SwiftUI.Binding(
            get: { service.options[field.key] ?? "" },
            set: { service.options[field.key] = $0.isEmpty ? nil : $0 },
        )
    }

    /// 多行字段（提示词）没填时显示默认值，方便在默认值基础上修改
    private var multilineOption: SwiftUI.Binding<String> {
        SwiftUI.Binding(
            get: { service.options[field.key] ?? field.defaultValue },
            set: { service.options[field.key] = $0 == field.defaultValue ? nil : $0 },
        )
    }

    private func scheduleSave(_ value: String) {
        saveTask?.cancel()
        let key = service.secretKey(field.key)
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                try secrets.setSecret(value.trimmingCharacters(in: .whitespacesAndNewlines), for: key)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
