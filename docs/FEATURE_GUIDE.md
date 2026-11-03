# 如何新增一个功能

> 写给人，也写给 AI Agent。按步骤做，不要自己发明结构。

## 1. 生成脚手架

```sh
make new-feature NAME=ColorPicker ID=colorPicker
```

会生成：

```
Packages/MAIO/Sources/FeatureColorPicker/
├── README.md
├── ColorPickerFeature.swift
├── ColorPickerCommands.swift
├── ColorPickerSettings.swift
├── Domain/
├── Infrastructure/
└── UI/
Packages/MAIO/Tests/FeatureColorPickerTests/
```

并自动在 `Package.swift` 的 `features` 列表、`App/FeatureCatalog.swift` 中注册（功能 target 只依赖 `MAIOKit`、`MAIOUI`）。
新功能默认 `enabledByDefault: false`，完成后再改成 `true`。

## 2. 填写 manifest

在 `ColorPickerFeature.swift` 中声明：id、名称、图标、所需权限、命令列表、默认快捷键。
命令 ID 格式固定为 `<featureID>.<verb>`，例如 `colorPicker.pick`。

## 3. 实现命令

- `Commands.swift` 只负责解析参数、调用 Domain / Infrastructure，不写业务逻辑。
- 业务逻辑放进 `Domain/`，并且**不 import AppKit**，保证可以单测。
- 和系统打交道的代码放进 `Infrastructure/`。
- 视图放进 `UI/`，优先复用 `MAIOUI` 组件。

## 3.5 实时输入（滚轮等）

需要在事件到达 App 之前修改或吞掉指针事件时，实现 `RealtimeInputFilter`，放进 `Realtime/` 目录，在 `activate()` 中用 `context.input.registerFilter` 注册。过滤器在 tap 线程上同步执行：只读不可变配置快照，不访问主线程，不阻塞。设置变化时注销旧过滤器、注册新的（或让过滤器持有 `Mutex` 保护的快照）。

## 4. 需要别的功能帮忙？

**不要 import 其他功能。** 按以下顺序处理：

1. 对方已有契约（`MAIOKit/Contracts/`）→ 直接 `context.commands.perform(...)`。
2. 对方没有契约 → 在 `MAIOKit/Contracts/` 新增契约，由对方实现。这属于 MAIOKit 变更，需要在 PR / 提交说明里写清楚原因。
3. 需要的是一项新的**系统能力**，而且两个以上功能都会用到（例如"获取窗口列表"）→ 提议在 `MAIOKit/Services/` 新增服务协议，并在 `MAIOCore` 中实现。**需要先写 ADR。**

## 5. 注册

脚手架已经完成注册。手动新建时：在 `Package.swift` 的 `features` 数组和 `App/FeatureCatalog.swift` 中各加一行，这是除新目录之外仅有的两处改动。

## 6. 测试并验收

- `Tests/Feature<Name>Tests/` 中：Domain 写纯单测；整体流程用 `FakeFeatureContext` 测"activate → perform → 断言"。
- 运行 `make check`，必须全部通过。
- 更新功能自己的 `README.md`：命令表、设置项、权限、已知限制。

## 自查清单

- [ ] 没有 import 其他 `Feature*` 或 `MAIOCore`
- [ ] 没有直接使用 `UserDefaults`、全局单例、`NotificationCenter` 做跨功能通信
- [ ] 没有自己创建 CGEventTap（需要原始按键时用 `context.input.beginKeyboardSession`）
- [ ] `deactivate()` 释放了全部资源（监听、窗口、定时器、Task）
- [ ] 设置结构体有默认值和 `schemaVersion`
- [ ] 单个文件不超过 400 行
- [ ] `make check` 全绿
