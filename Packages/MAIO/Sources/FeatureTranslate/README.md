# 翻译（`translate`）

选中文字按 ⌥Q 翻译；没有选中文字时打开输入框。所有启用的翻译源并行请求，结果按设置里的顺序显示；大模型逐字输出。

## 命令

| 命令 | 参数 | 说明 |
|---|---|---|
| `translate.show` | 无 | 默认绑定 ⌥Q。行为由 `hotkeyBehavior` 决定 |
| `translate.selection` | 无 | 只翻译选中的文字，没有选中时提示 |
| `translate.input` | 无 | 打开空的输入框 |
| `translate.text` | `text` | 契约 `TranslateTextContract`：打开窗口并翻译传入的文字（M5 截图 OCR 调用） |

窗口内：回车翻译，⇧回车换行，Esc 或 ⌘W 关闭；输入框和选中的译文里 ⌘A、⌘C、⌘V 等标准快捷键可用；📌 固定后失去焦点不关闭；每张结果卡片可以复制、折叠、失败时重试。

## 设置项（`config/features/translate.json`）

| 字段 | 默认值 | 说明 |
|---|---|---|
| `services` | Google、必应、腾讯交互（启用）；Apple、DeepSeek（关闭） | 翻译源实例列表，顺序即显示顺序。密钥不在这里 |
| `hotkeyBehavior` | `smart` | `smart` 有选中就翻译否则打开输入框 / `inputOnly` / `selectionOnly` |
| `targetLanguage` | `zh-Hans` | 目标语言 |
| `secondTargetLanguage` | `en` | 原文已是目标语言时改译成它 |
| `removeLineBreaks` | `true` | 自动删除换行（PDF 断行） |
| `windowPosition` | `center` | `center`（屏幕正中间，结果变多时上下同时扩展）/ `followMouse` / `remember`。v2 把旧的 `followMouse` 迁移成 `center`。只管直接打开输入框的情况 |
| `selectionWindowPosition` | `center` | 翻译选中文字时：`center` / `mouse` / `nearSelection`（选中文字下方，放不下放上方；App 不提供选中位置时用鼠标处） |
| `closeOnBlur` | `true` | 失去焦点时关闭 |
| `fontSize` | `14` | |
| `historyEnabled` / `historyLimit` | `true` / `500` | 历史存在 `data/translate/history.json` |

API Key 存在系统钥匙串（ADR-0009）：service `app.maio.translate`，account `<服务实例 id>.<字段>`。

## 翻译源

| 源 | 文件 | 说明 |
|---|---|---|
| Google | `GoogleProvider` | 网页 gtx 接口，免费；查单词返回音标和释义（词典模式） |
| 必应 | `BingProvider` | 网页翻译器 `ttranslatev3`，先抓页面拿 IG/IID/key/token + cookie，缓存到过期；启动时预热 |
| 腾讯交互翻译 | `TransmartProvider` | transmart.qq.com，免费 |
| Apple 翻译 | `AppleProvider` | 系统 Translation 框架，离线；需用户自己下载语言包 |
| 大模型 | `OpenAICompatibleProvider` | OpenAI 兼容接口 + SSE 流式；预设见 `LLMPreset`（DeepSeek、OpenAI、Gemini、智谱、Kimi、通义、硅基流动、Ollama） |
| DeepL、百度、有道、腾讯云、阿里、火山、彩云、小牛 | 各自的 `*Provider` | 官方接口，需要 Key。签名逻辑是可测试的静态函数 |

新增一个源：`Domain/ProviderKind.swift` 加 case → `Domain/ProviderCatalog.swift` 写 spec（设置表单自动生成）→ `Infrastructure/Providers/` 写实现 → 在 `ProviderFactory` / `KeyedProviders` 注册。

## 权限

辅助功能：读取选中文字（`kAXSelectedTextAttribute`）；读不到时模拟 ⌘C，读完恢复剪贴板。

## 测试

- 单测：`swift test --filter FeatureTranslateTests`
- 真实联网（免费源 + Apple）：`MAIO_NETWORK_TESTS=1 swift test --filter NetworkIntegration`

## 参考

`references/pot-desktop/src/services/translate/<源>/`（请求格式）、`src/window/Translate/`（窗口交互）。

## 已知限制

- Google、必应、腾讯交互翻译是非官方网页接口，对方改版可能失效（Yandex 免费接口 2026-11 已失效，所以没做）。
- 腾讯云、阿里、火山的签名只用官方示例验证过，没有用真实 Key 跑通（假 Key 在校验签名前就被拒绝）。
- 有道签名的截断规则按 Unicode 标量计数，含 emoji 的长文本可能签名失败。
- 模拟 ⌘C 时，VS Code 等编辑器在没有选中文字的情况下会复制整行，可能把当前行当作选中文字翻译。
- 暂不支持：朗读、翻译回原文、截图翻译（M5 通过 `translate.text` 契约接入）。
