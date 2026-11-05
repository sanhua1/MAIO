# ADR-0021：功能可以列出当前可用的命令

- 状态：已采纳
- 日期：2026-11-05

## 背景

启动器（M7 P4）要像 Raycast 一样，能搜到并执行 MAIO 自己的命令（"截图""剪贴板历史""重启 Finder"……）。
`CommandRegistrar` 现在只能按 ID 执行命令、查询某个 ID 是否可用，功能拿不到"现在有哪些命令"。
宿主（`MAIORuntime.allCommands`）能列出全部命令，但它在 MAIOCore 里，功能不能 import；而且它包含未启用功能声明的命令，这些命令执行不了。

## 决定

在 `CommandRegistrar` 上新增一个只读方法：

```swift
/// 当前能执行的全部命令（已启用的功能实际注册了的），按功能在目录里的顺序排列
func availableCommands() -> [AvailableCommand]
```

`AvailableCommand`（`MAIOKit/Command/AvailableCommand.swift`）：命令描述 `descriptor`、所属功能的 `featureID`、`featureName`（显示名）、`featureSymbol`（SF Symbol）。

- 实现：`CommandBus` 记下各功能的 manifest（`MAIORuntime` 初始化时传入），列出时按功能在目录里的顺序排列；同一功能内按 manifest 里声明的顺序，没在 manifest 里声明的放在最后。
- 只列出，不给修改能力；执行仍然走 `perform`。
- 不提供变化通知：调用方需要时再取一次（启动器每次打开面板时取，几十个命令，开销可以忽略）。
- `MAIOTesting.FakeCommandRegistrar` 返回它注册过的命令，功能名用功能 ID 代替。

## 备选方案

- **用 manifest 里声明的命令**：功能拿不到其他功能的 manifest，而且未启用的功能也声明了命令，列出来执行不了。
- **新增一个"命令目录"服务协议**：只有一个方法，放在 `CommandRegistrar` 上更直接，调用方本来就要用它执行命令。
- **加变化流（AsyncStream）**：目前唯一的调用方只在打开面板时用，没有必要。

## 后果

- `CommandRegistrar` 多了一个必须实现的方法（宿主的 `ScopedCommandRegistrar` 和测试用的 Fake 已实现）。
- 调用方自己决定列出哪些：启动器不列出自己的命令，也不列出有必填参数的命令（第一版没有参数输入界面）。
