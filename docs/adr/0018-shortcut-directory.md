# ADR-0018：快捷键目录服务（跨功能的冲突检测）

- 状态：已采纳
- 日期：2026-11-05

## 背景

Finder 增强的每个快捷键都能改，用户要求"所有快捷键设置都支持冲突检测，实时提示"。冲突来自三处：

1. macOS 系统快捷键（聚焦搜索、输入法、截图……）：MAIOCore 的 `SystemShortcutManager` 知道；
2. MAIO 的快捷键绑定（快捷键页）：MAIOCore 的 `BindingStore` 知道；
3. 其他功能自己处理的按键（Finder 增强在 Finder 里的改键走按键过滤器，不是绑定）：只有那个功能自己知道。

功能不能 import MAIOCore，快捷键页（MAIOShell）也看不到功能内部的改键，两边都只能看到一半。

## 决定

在 MAIOKit 新增服务协议 `ShortcutDirectory`（`MAIOKit/Services/ShortcutDirectory.swift`），通过 `FeatureContext.shortcuts` 提供：

- `occupants(of:scope:)`：在某个作用范围内，这个组合键还被谁占用（系统快捷键 / MAIO 绑定 / 其他功能登记的键）。结果不含本功能自己登记的键，也不含本功能自己命令的绑定。
- `reserve(_:)`：功能登记"我在这些 App 里占用了这些键"（`ReservedShortcut`：组合键、作用范围、标题），整体替换；功能停用时宿主自动清空。

实现：`MAIOCore/Host/ShortcutReservations.swift`（`ShortcutReservations` 保存各功能的登记，`FeatureShortcutDirectory` 是给单个功能的视图）。
快捷键页（`BindingStatus`、`BindingEditor`）通过 `MAIORuntime.reservations` 提示"被 Finder 增强：剪切（在 Finder 里）占用"。

优先级（设置页据此决定提示是红色"不会生效"还是橙色"会覆盖"）：系统快捷键 → 按键过滤器（功能登记的键）→ MAIO 绑定 → App 自己的菜单快捷键。

## 备选方案

- **把 Finder 的改键做成普通绑定**：绑定只能"总是吞键"，做不到"重命名时放行"，见 ADR-0017。
- **在 MAIOKit 暴露 BindingStore / SystemShortcutManager 本身**：功能会拿到修改能力，接口面太大。

## 后果

- MAIOKit 新增一个协议和 `FeatureContext.shortcuts`；`MAIOTesting.FakeShortcutDirectory` 可以预置占用。
- 登记是"声明"，不影响按键实际怎么分发；功能要自己保证登记的和实际处理的一致（Finder 增强在每次设置变化时重新登记）。
