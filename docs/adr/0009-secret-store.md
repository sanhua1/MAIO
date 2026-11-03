# ADR-0009：密钥存储服务（SecretService）

- 状态：已采纳
- 日期：2026-11-03

## 背景

M4 翻译需要保存各翻译源的 API Key（DeepSeek、百度、腾讯云……）。之后截图上传、OCR 等功能也可能需要。
设置文件（`config/features/*.json`）是明文，用户可能同步或分享配置目录，不能存放密钥。

## 决定

- 在 `MAIOKit/Services/` 新增 `SecretService` 协议，通过 `FeatureContext.secrets` 提供给功能：
  - `secret(for:) -> String?`
  - `setSecret(_:for:) throws`（传 nil 表示删除）
- `MAIOCore/Platform/KeychainSecretStore.swift` 用系统钥匙串实现（`kSecClassGenericPassword`）：
  - service 为 `app.maio.<featureID>`，按功能隔离，功能之间读不到彼此的密钥；
  - account 为功能自己决定的键，例如 `<服务实例 ID>.apiKey`。
- `MAIOTesting` 提供内存实现 `InMemorySecrets`。
- 设置文件里只保存"有没有填"之外的非敏感字段，密钥只进钥匙串。

## 备选方案

- **功能自己调用 Security 框架**：会让每个功能重复写钥匙串代码，测试也无法替换。
- **存进设置文件，加简单混淆**：不安全，而且会被同步到别处。

## 后果

- FeatureContext 增加一个成员，所有实现（Host、Fake）同步更新。
- 钥匙串条目和代码签名绑定。换签名（例如换开发证书）后，第一次读取可能弹出系统授权框，或者需要重新填写 Key。
- 删除 MAIO 不会自动清除钥匙串条目，用户可以在"钥匙串访问"中搜索 `app.maio` 手动删除。
