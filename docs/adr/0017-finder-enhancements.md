# ADR-0017：Finder 增强不注入，用键盘实时过滤器 + 辅助功能 + AppleScript + Finder 配置

- 状态：已采纳
- 日期：2026-11-05

## 背景

用户是重度 Windows 用户，希望 Finder 像资源管理器一样好用（回车打开、F2 重命名、剪切粘贴、Delete 删除、
新建文本文件、在终端打开……），并且每一项都是 MAIO 里可以单独开关的选项。

改 Finder 有两类做法：

1. **注入 Finder 进程**（XtraFinder、TotalFinder、MacForge 的做法）：能改任何行为和外观，但必须关闭 SIP，
   Apple 芯片上还要开 arm64e 预览 ABI，每次系统更新都可能失效，也不能要求普通用户这样做。
2. **在 Finder 外面做**：改键、读 Finder 状态、让 Finder 执行操作、改 Finder 的隐藏配置。

## 决定

不注入（用户确认），功能模块 `FeatureFinder` 只用公开接口：

1. **新增 MAIOKit 扩展点：键盘实时过滤器** `RealtimeKeyFilter`（`MAIOKit/Services/InputService.swift`）。
   - 在键盘 tap 线程上同步调用，收到 **keyDown**（含按住重复），返回 `pass` / `consume` / `replace(KeyChord)`；
     也收到 **flagsChanged**，但只能观察、不能吞（速查面板靠它判断"只按住了 ⌘"）。
   - 位置：键盘会话、快捷键录制之后，**快捷键匹配之前**（Finder 里的改键优先于用户的全局快捷键；
     过滤器自己判断前台 App，不在 Finder 里时一律 `pass`）。
   - `replace` 由引擎在 tap 线程上立即发出合成按键（带 MAIO 标记，不会再进过滤器），所以和后面的真实按键顺序一致；
     被吞掉的 keyDown 对应的 keyUp 也会被吞掉。
   - 注册：`InputService.registerKeyFilter(_:)`，注销与指针过滤器共用 `removeFilter(_:)`，功能停用时宿主自动清理。
   - 约束与指针过滤器相同：不访问主线程、不阻塞、不做 IO，只读 `Mutex` 保护的快照。
2. **"正在输入文字"由主线程维护，tap 线程只读快照。** Finder 的重命名框、搜索框、"前往文件夹"输入框获得焦点时，
   回车、⌫ 等必须原样放行。`FinderFocusMonitor` 用 AXObserver 监听 Finder 的 `AXFocusedUIElementChanged`，
   焦点是文本框（AXTextField / AXTextArea / AXComboBox）就把过滤器标成"输入中"；Finder 到前台时、以及在前台期间每 0.5 秒再查一次兜底。
   不在 tap 线程上查 AX：那是跨进程调用，Finder 卡住时会拖慢所有按键。
3. **让 Finder 执行操作用 AppleScript**（`insertion location`、`make new file`、`select`），在后台线程执行。
   文件由 Finder 自己创建，MAIO 不需要"文件和文件夹"授权；第一次使用时系统会弹"自动化"授权。
4. **Finder 的隐藏设置直接写 Finder 自己的配置域**（`com.apple.finder`、`com.apple.desktopservices`、全局域），
   用 `CFPreferencesSetAppValue`，改完提示"重启 Finder"。这不是 MAIO 的设置，所以不经过 `SettingsService`，
   也不使用 `UserDefaults`（架构规则仍然成立）；只在 `FeatureFinder/Infrastructure/FinderPreferences.swift` 中出现。
   关闭某项 = 删除这个键（恢复系统默认），不写"反向的值"。

## 备选方案

- **用快捷键绑定实现改键**（作用范围设为 Finder）：吞键在 tap 线程同步决定，绑定只能"总是吞"，
  命令到主线程再判断是否在重命名、再补发原键，会和后面的真实按键乱序（快速输入 "ab⌫c" 时 ⌫ 跑到 c 后面）。
- **tap 线程上直接查 AX 焦点**：最准，但阻塞 tap 线程，违反实时约束。
- **Finder Sync 扩展**（右键菜单、工具栏按钮）：需要新增 App 扩展 target 和签名、打包流程，放到第二期，另写 ADR。
- **注入**：见背景，不做。

## 后果

- 外观、列表结构、地址栏样式都改不了；双栏、树形导航只能用窗口平铺近似。
- 只对 Finder 生效，其他 App 里的"打开 / 保存"面板不受影响。
- 焦点判断依赖 Finder 的辅助功能信息；如果某个 macOS 版本里 Finder 重命名框不报告焦点变化，
  0.5 秒轮询兜底，期间可能把一次回车当成"打开"。
- MAIOKit 新增一个协议和一个方法；`MAIOTesting.FakeInputService` 同步实现。
