# MAIO 架构设计

> 状态：v0.3（2026-11-02），已确认，M0 实施中
> v0.3：与 M0 实现对齐——新增 MAIOShell 层；`Binding` 更名为 `CommandBinding`（避免与 SwiftUI.Binding 冲突）
> v0.2：快捷键引擎扩展为输入引擎（键盘 + 指针），新增滚动功能、参考项目规范、进度文档
> 本文是项目的"宪法"。代码与本文冲突时，要么改代码，要么先发 ADR 改本文，不允许悄悄偏离。

---

## 0. 设计目标（按优先级）

1. **可扩展**：新增一个功能 = 新增一个目录 + 在一处注册，不改动任何已有功能的代码。
2. **防腐化**：边界由**编译器**强制，而不是靠自觉。AI Agent 写错依赖时，编译直接失败。
3. **局部性**：任何一个功能，都能只读它自己的目录 + `MAIOKit` 就完全理解。这对 Agent 尤其关键，因为它的上下文有限。
4. **故障隔离**：单个功能启动失败或缺少权限，不影响其他功能和主程序。
5. **可测试**：核心逻辑不依赖真实系统权限，用假实现就能跑单测。

非目标：跨平台、App Store 上架、第三方插件市场（运行时动态加载）。功能都是编译期集成的"内置插件"。

---

## 1. 核心思想：一切皆命令（Command-centric）

```
   触发器 Trigger                 命令总线 CommandBus              功能 Feature
 ┌──────────────────┐          ┌──────────────────────┐        ┌─────────────────┐
 │ 快捷键 Fn+A       │──┐       │                      │   ┌───▶│ Clipboard       │
 │ 菜单栏点击        │──┼──────▶│  CommandID + 参数     │───┼───▶│ Screenshot      │
 │ URL maio://run/… │──┤       │  → 查表 → 调用 handler │   ├───▶│ Translate       │
 │ （未来）手势/CLI  │──┘       │                      │   └───▶│ SystemActions   │
 └──────────────────┘          └──────────────────────┘        └─────────────────┘
          ▲                                                          │
          └──────────── CommandBinding（用户配置：触发器 → 命令 + 参数）─────┘
```

- **功能（Feature）只做一件事：声明并实现命令。** 比如 `clipboard.showPanel`、`screenshot.captureRegion`、`translate.selection`。
- **触发器（Trigger）只做一件事：产生"执行某命令"的请求。** 快捷键、菜单、URL Scheme 都是触发器。
- **绑定（Binding）是用户数据**，把触发器连到命令上。BetterTouchTool 式的"任意组合键 → 任意动作"，就是这个模型的自然结果。
- 通用动作也是命令，由内置功能 `SystemActions` 提供：打开 App、打开 URL、执行 Shell、执行 AppleScript、运行"快捷指令"、发送按键（键位重映射）。

好处：功能之间、功能和快捷键之间**零耦合**。新增功能不用碰快捷键代码，新增触发方式也不用碰任何功能代码。

---

## 2. 分层与模块

```
┌────────────────────────────────────────────────────────────┐
│ App（入口）  唯一知道"所有功能"的地方：FeatureCatalog.swift   │
├────────────────────────────────────────────────────────────┤
│ MAIOShell  组合根 + 宿主 UI：菜单栏、设置窗口、绑定编辑器、HUD │
└───────────────┬───────────────────────────┬────────────────┘
                │                           │
      ┌─────────▼─────────┐     ┌───────────▼──────────────────────────┐
      │ MAIOCore（运行时）  │     │ Feature*（功能模块，彼此完全不可见）    │
      │ 宿主/总线/快捷键引擎 │     │ Clipboard │ Switcher │ Translate │ … │
      │ 设置/权限/存储/平台  │     └───────────┬──────────────────────────┘
      └─────────┬─────────┘                 │
                │          ┌────────────────▼───┐
                │          │ MAIOUI（共享 UI 组件）│
                │          └────────────────┬───┘
      ┌─────────▼───────────────────────────▼─────┐
      │ MAIOKit（SDK：协议 + 值类型 + 跨功能契约）    │  ← 最稳定，改动要发 ADR
      └───────────────────────────────────────────┘
```

### 依赖规则（由 SPM target 依赖强制，并由 `scripts/check-architecture.sh` 二次校验）

| 模块 | 可以依赖 | 禁止依赖 |
|---|---|---|
| `MAIOKit` | 仅 Apple 基础框架（Foundation、CoreGraphics、SwiftUI 类型） | 任何 MAIO 模块、任何第三方库 |
| `MAIOUI` | `MAIOKit`、SwiftUI/AppKit | `MAIOCore`、`Feature*` |
| `MAIOCore` | `MAIOKit`、Apple 框架 | `Feature*`、`MAIOUI`、`MAIOShell` |
| `MAIOShell` | `MAIOKit`、`MAIOUI`、`MAIOCore` | `Feature*`（功能列表由 App 传入） |
| `Feature*` | `MAIOKit`、`MAIOUI`、Apple 框架、白名单内的第三方库 | **`MAIOCore`、其他 `Feature*`** |
| `MAIOTesting` | `MAIOKit` | 其他 |
| `App` | `MAIOShell`、各 `Feature*` | — |

**最关键的两条：**
- **功能不能 import 其他功能。** 需要协作时走"契约命令"（§4.3）。
- **功能不能 import `MAIOCore`。** 功能只能看到 `MAIOKit` 里的协议，具体实现由 App 注入（依赖倒置）。这样功能拿不到全局单例，也不可能绕过宿主去直接操作 event tap。

---

## 3. 目录结构

```
mac-all-in-one/
├── CLAUDE.md                  # Agent 工作守则（必读；本地文件，不在公开仓库里）
├── AGENTS.md                  # 指向 CLAUDE.md，给其他 Agent 用（本地文件）
├── Makefile                   # make bootstrap / build / test / check / run / install / new-feature
├── Config/                    # Base.xcconfig；Signing.local.xcconfig（本机签名，不进 git）
├── project.yml                # XcodeGen 配置，.xcodeproj 由它生成，不提交 git
│
├── App/                       # 很薄的 App 壳
│   ├── MAIOApp.swift          # @main，菜单栏 App（LSUIElement）
│   ├── FeatureCatalog.swift   # ★ 注册所有功能的唯一位置
│   ├── Info.plist
│   └── MAIO.entitlements      # 非沙盒
│
├── Packages/MAIO/
│   ├── Package.swift          # 所有模块边界都在这里声明
│   ├── Sources/
│   │   ├── MAIOKit/
│   │   │   ├── Feature/       # Feature 协议、FeatureManifest、FeatureContext
│   │   │   ├── Command/       # CommandID、CommandDescriptor、CommandInvocation、CommandBus 协议
│   │   │   ├── Trigger/       # Trigger、KeyChord、Binding
│   │   │   ├── Contracts/     # ★ 跨功能契约（§4.3）
│   │   │   └── Services/      # 服务协议：Input、Settings、Storage、Permissions、Overlay、SystemEvent
│   │   ├── MAIOUI/            # 设计系统：浮动面板、HUD、快捷键录制器、设置表单组件
│   │   ├── MAIOCore/
│   │   │   ├── Host/          # FeatureHost：生命周期、故障隔离
│   │   │   ├── Commands/      # CommandBus 实现
│   │   │   ├── Input/         # InputEngine：键盘 tap、指针 tap（§5），全项目唯一创建 CGEventTap 的地方
│   │   │   ├── Bindings/      # 绑定存储、冲突检测
│   │   │   ├── Settings/      # 配置读写、版本迁移
│   │   │   ├── Permissions/   # TCC 权限检测与引导
│   │   │   └── Platform/      # 对 CGEventTap / AX / NSWorkspace 的薄封装
│   │   ├── MAIOShell/         # 组合根（MAIOAppController）、菜单栏、设置窗口、HUD
│   │   ├── MAIOTesting/       # 所有服务协议的内存假实现，供单测使用
│   │   ├── FeatureSystemActions/
│   │   ├── FeatureScroll/
│   │   ├── FeatureClipboard/
│   │   ├── FeatureSwitcher/
│   │   ├── FeatureTranslate/
│   │   └── FeatureScreenshot/
│   └── Tests/
│       ├── MAIOCoreTests/
│       └── Feature<Name>Tests/
│
├── Templates/Feature/         # 新功能脚手架模板
├── scripts/                   # check-architecture.sh、new-feature.sh、fetch-references.sh 等
├── references/                # 参考用的开源项目源码（只读，不进 git，见 references/README.md）
└── docs/
    ├── ARCHITECTURE.md        # 本文
    ├── FEATURE_GUIDE.md       # 如何新增一个功能（Agent 照做即可）
    ├── PROGRESS.md            # 工作进度与交接记录（每个 session 开始读、结束更新；本地文件）
    └── adr/                   # 架构决策记录
```

每个功能目录的内部结构固定：

```
FeatureClipboard/
├── README.md                  # 用途、命令列表、设置项、所需权限（Agent 的入口文档）
├── ClipboardFeature.swift     # 实现 Feature 协议：manifest + activate/deactivate
├── ClipboardCommands.swift    # 命令 handler，只做参数解析和调用，不写业务逻辑
├── ClipboardSettings.swift    # Codable 设置结构 + 默认值 + 版本迁移
├── Domain/                    # 纯逻辑，不 import AppKit，100% 可单测
├── Infrastructure/            # 和系统打交道：NSPasteboard 监听、持久化
├── Realtime/                  # （可选）在 tap 线程上运行的实时过滤器，约束见 §5.4
└── UI/                        # SwiftUI 视图：面板、设置页
```

---

## 4. MAIOKit：SDK 契约

### 4.1 Feature 协议

```swift
@MainActor
public protocol Feature: AnyObject {
    /// 静态元信息，宿主不实例化功能就能读取（用于设置页、权限引导、命令列表）
    static var manifest: FeatureManifest { get }

    init(context: FeatureContext)

    /// 启用：注册命令 handler、启动监听。抛错时宿主会隔离该功能，不影响其他功能
    func activate() async throws
    /// 停用：必须释放全部资源（监听、窗口、定时器）。宿主保证会调用
    func deactivate() async

    /// 设置页（可选）。宿主把它放进统一设置窗口的侧边栏
    func makeSettingsView() -> AnyView?
}

public struct FeatureManifest: Sendable {
    public let id: FeatureID                       // "clipboard"，全局唯一，永不改名
    public let displayName: String                 // "剪贴板"
    public let symbol: String                      // SF Symbol 名
    public let summary: String
    public let requiredPermissions: Set<Permission> // .accessibility / .inputMonitoring / .screenRecording
    public let commands: [CommandDescriptor]       // 声明本功能提供的所有命令
    public let defaultBindings: [DefaultBinding]   // 出厂快捷键（用户可改）
    public let enabledByDefault: Bool
}
```

### 4.2 FeatureContext：功能能接触到的全部世界

```swift
@MainActor
public protocol FeatureContext {
    var featureID: FeatureID { get }
    var commands: CommandRegistrar { get }      // 注册自己的命令 / 调用别人的命令
    var input: InputService { get }             // 键盘会话、指针实时过滤器、发送合成事件（§5）
    var settings: SettingsService { get }       // 只能读写自己命名空间的设置
    var storage: StorageService { get }         // 只能访问 ~/Library/Application Support/MAIO/<featureID>/
    var permissions: PermissionService { get }
    var overlay: OverlayService { get }         // 浮动面板、HUD、提示
    var events: SystemEventService { get }      // 前台 App 变化、外观变化等系统事实
    var logger: Logger { get }                  // 已按 featureID 分类的 os.Logger
}
```

**功能拿不到任何全局单例。** 需要的能力都从 context 里来，所以测试时可以把整个 context 换成 `MAIOTesting` 里的假实现。

### 4.3 跨功能协作：契约命令（Contracts）

场景：截图 OCR 出文字后，想直接交给翻译功能。

错误做法：`FeatureScreenshot` 去 import `FeatureTranslate`（编译器会拒绝）。

正确做法：在 `MAIOKit/Contracts/` 里定义一个**类型安全的契约**，双方只依赖契约：

```swift
// MAIOKit/Contracts/TranslateContracts.swift
public enum TranslateText: CommandContract {
    public static let id: CommandID = "translate.text"
    public struct Input: Codable, Sendable { public var text: String; public var targetLanguage: String? }
    public typealias Output = Void
}

// 提供方 FeatureTranslate
context.commands.register(TranslateText.self) { input in try await translator.show(input.text) }

// 调用方 FeatureScreenshot
try await context.commands.perform(TranslateText.self, TranslateText.Input(text: ocrText))
```

如果提供方没启用，`perform` 会抛出 `CommandError.unavailable`，调用方自己决定降级方式（比如隐藏"翻译"按钮）。

**规则：请求用命令，事实用事件。** "请翻译这段文字"是命令；"前台 App 变了"是事件（`SystemEventService`）。不使用 NotificationCenter 做跨功能通信。

### 4.4 命令描述与参数

```swift
public struct CommandDescriptor: Sendable {
    public let id: CommandID                 // "<featureID>.<verb>"，如 "screenshot.captureRegion"
    public let title: String                 // 用户在绑定编辑器里看到的名字
    public let parameters: [ParameterSpec]   // 声明参数，绑定编辑器据此自动生成表单
}
```

只在功能内部使用的命令走 `CommandDescriptor` + 字典参数；需要被其他功能调用的命令才升级成 `CommandContract`。

---

## 5. 输入引擎（InputEngine）

这是整个项目风险最高的部分，单独设计。它统一接管**键盘**（全局快捷键、键盘会话）和**指针设备**（滚轮反转、平滑滚动，以后还有鼠标侧键、手势）。

> 反面教材：vorssaint-utils 在 25 个不同的文件里各自创建 CGEventTap，tap 之间的顺序、相互干扰、恢复逻辑都不可控。MAIO 规定：**CGEventTap 只能在 `MAIOCore/Input/` 中创建。**

### 5.1 总体结构

```
MAIOCore/Input/
├── KeyboardTap   独立线程：keyDown / keyUp / flagsChanged   → 快捷键流水线（§5.2）
└── PointerTap    独立线程：scrollWheel / otherMouse*         → 实时过滤器链（§5.4）
```

键盘和指针分成两个 tap、两个线程：滚轮事件频率很高（平滑滚动时每秒上百个），不能让它影响快捷键的响应延迟。

### 5.2 快捷键流水线

```
 KeyboardTap（独立线程 + 独立 RunLoop，绝不在主线程）
   │  keyDown / keyUp / flagsChanged
   ▼
 Normalizer   → KeyEvent { keyCode, modifiers: {⌘ ⌃ ⌥ ⇧ fn}, 左右修饰键, isRepeat }
   ▼
 SessionRouter → 如果有活跃的 KeyboardSession（例如切换器正在显示），事件全部交给它
   ▼
 Matcher      → 在 [KeyChord: [Binding]] 字典中 O(1) 查找，再按作用域过滤（全局 / 指定 App）
   ▼
 Decision     → 同步返回：吞掉事件，或放行（必须在 1ms 量级内完成，否则系统会禁用 tap）
   ▼ （异步回主线程）
 CommandBus.perform(binding.command, binding.arguments)
```

### 5.3 通用要点

- **配置是不可变快照。** 用户修改绑定或滚动设置时，在主线程构建新快照，再原子替换给 tap 线程（`Synchronization.Mutex` / `Atomic`）。tap 回调里不等锁、不碰 `@MainActor`、尽量不分配内存。
- **Tap 自愈**：收到 `tapDisabledByTimeout` / `tapDisabledByUserInput` 时自动重新启用，并记录日志。
- **合成事件打标记**：MAIO 自己发出的事件（平滑滚动、键位重映射）都通过 `eventSourceUserData` 打上标记，引擎据此识别，避免自己处理自己发出的事件、陷入死循环。功能只能通过 `context.input.post(...)` 发送合成事件，由引擎统一打标记。
- **前台 App 快照**：引擎维护一个原子更新的"当前前台 App bundleID"，tap 线程上的按 App 规则直接读取，不用去问主线程。
- **录制模式**：快捷键录制器激活时，引擎暂停匹配，原始按键交给录制器。
- **键盘会话 `KeyboardSession`**：Alt+Tab 这类功能需要"按住 ⌥ 期间持续接收 Tab / 方向键，松开 ⌥ 时确认"。功能通过 `context.input.beginKeyboardSession(...)` 获得一个 `AsyncStream<KeyEvent>`，会话结束前事件都归它。这是功能拿到原始按键的**唯一**途径。
- **扩展的触发形式**，以后加，不改模型：修饰键双击（双击 ⌘）、长按、单独按 Fn、鼠标侧键。都是 `Trigger` 枚举的新 case，加一个 Matcher 状态机即可。
- **冲突检测**：保存绑定时检查与其他绑定、已知系统快捷键的冲突，在 UI 上提示。

### 5.4 指针实时过滤器（RealtimeInputFilter）

滚轮反转、平滑滚动这类功能必须在 tap 线程上**同步**修改或吞掉事件，无法走"异步回主线程"的命令模型。为此 MAIOKit 提供一个受严格约束的扩展点：

```swift
/// 在 tap 线程上同步调用。必须是 Sendable，不得访问 @MainActor 状态，不得阻塞。
public protocol RealtimeInputFilter: Sendable {
    func process(_ event: inout PointerEvent, _ environment: RealtimeEnvironment) -> FilterDecision
}
public enum FilterDecision: Sendable { case pass, consume }

public struct PointerEvent {                 // 对 CGEvent 的类型安全封装，不暴露 CGEvent 本身
    public var deltaY: Double, deltaX: Double
    public let device: PointerDeviceKind     // .mouseWheel / .trackpad / .magicMouse / .remote（远程桌面）
    public let phase: ScrollPhase?           // 触控板手势阶段、惯性阶段
    public let isSynthetic: Bool             // 是否为 MAIO 自己发出的事件
    // ...
}
public struct RealtimeEnvironment: Sendable {
    public let frontmostBundleID: String?
    public let modifiers: KeyModifiers
}

// 功能在 activate() 中注册，返回的 token 在 deactivate() 中注销
let token = context.input.registerFilter(myFilter, for: .scrollWheel, stage: .transform)
```

- 过滤器按固定阶段排序执行：`.observe`（只读）→ `.transform`（反转、步长）→ `.smooth`（吞掉原事件，交给插值器）。顺序由阶段决定，不依赖注册先后。
- 实时代码集中放在功能目录的 `Realtime/` 子目录里，便于审查；`check-architecture.sh` 校验其中没有 `@MainActor`、`DispatchQueue.main`、`NSApp` 等。
- 平滑滚动需要按屏幕刷新率持续输出插值后的事件：功能可以自己持有一个 display link 线程（macOS 14+ 用 `NSScreen.displayLink`），但发事件必须走 `context.input.post(...)`。

### 5.5 滚动功能（FeatureScroll）的设计要点

参考 Mos 的成熟做法（`references/Mos/Mos/ScrollCore/`）：

| 能力 | 做法 |
|---|---|
| 区分鼠标和触控板 | 依据 `scrollWheelEventIsContinuous` 和 phase 字段；默认**只处理鼠标滚轮**，不碰触控板 |
| 反转 | 纵向、横向分别开关；只作用于鼠标（触控板保持系统"自然滚动"设置） |
| 步长 | 单次滚动的最小跨度，过小的 delta 归一到设定步长 |
| 平滑 | 吞掉原始事件，按"速度 / 持续时间"两个参数在每个刷新帧输出插值，模拟带惯性的触控板滚动 |
| 按 App 例外 | 某些 App（游戏、远程桌面、绘图软件）关闭平滑或使用单独参数 |
| 按住修饰键 | 例如按住 ⇧ 时纵向转横向、按住 ⌥ 时临时减速 |
| 远程桌面 | 来源本身已是连续事件时跳过平滑，避免重复平滑 |

这个功能的"领域逻辑"（插值曲线、步长归一、按 App 匹配）放在 `Domain/`，全部是纯函数，可以用固定输入序列做确定性单测。

### 5.3 Fn 键风险（M0 阶段必须先验证）

`CGEventFlags.maskSecondaryFn` 可以识别 Fn 修饰位。但 🌐/Fn 相关的部分系统快捷键在更底层处理，普通 event tap 可能吞不掉。M0 先写一个原型逐一测试，结论记入 `docs/adr/0004-fn-key-strategy.md`。备选方案按代价从低到高：

1. 引导用户在系统设置里把 🌐 键改成"无操作"，event tap 就足够了；
2. 改用 IOHIDManager 在 HID 层监听；
3. 引入 Karabiner 的 DriverKit 虚拟键盘（代价最高，最后考虑）。

`InputService` 协议不暴露上述任何细节，换方案不影响功能代码。

---

## 6. 用户数据：设置与绑定

```
~/Library/Application Support/MAIO/
├── config/
│   ├── app.json               # 全局设置（启用了哪些功能、登录启动等）
│   ├── bindings.json          # 所有快捷键绑定（手写可编辑，方便备份、同步、diff）
│   └── features/
│       ├── clipboard.json
│       └── translate.json
└── data/
    ├── clipboard/             # 功能私有数据（历史数据库、缓存）
    └── screenshot/
```

- 每个功能的设置是一个 `Codable` 结构体，带 `schemaVersion` 和 `migrate(from:)`。**字段只增不删**；要删字段，先在迁移里处理。
- 设置是可观察的：功能订阅自己设置的变化，实时生效，不需要重启。
- 解析失败时，备份坏文件，用默认值启动，并发出提示。绝不因为配置损坏而崩溃。
- 敏感信息（翻译 API Key 等）存 Keychain，不写进 JSON。
- 不直接使用 `UserDefaults`。

`bindings.json` 示例：

```json
{
  "schemaVersion": 1,
  "bindings": [
    { "id": "6F1C…", "trigger": { "hotkey": "fn+a" },
      "command": "system.openApp", "arguments": { "bundleID": "com.apple.ActivityMonitor" },
      "scope": "global", "enabled": true },
    { "id": "A2B9…", "trigger": { "hotkey": "opt+tab" },
      "command": "switcher.show", "arguments": {}, "scope": "global", "enabled": true }
  ]
}
```

---

## 7. 生命周期与故障隔离

```
App 启动
 → 读取 app.json，确定启用的功能
 → FeatureHost 遍历 FeatureCatalog：
     对每个启用的功能：
       1. 检查 manifest.requiredPermissions，缺权限 → 状态 = .needsPermission（不启动，设置页显示引导）
       2. 创建该功能专属的 FeatureContext
       3. try await feature.activate()
          成功 → 状态 = .running
          失败 → 状态 = .failed(error)，记录日志，HUD 提示，继续启动下一个
 → 加载 bindings.json，构建快捷键表（引用未启用功能命令的绑定会显示为"不可用"，不删除）
 → 启动 InputEngine（无辅助功能权限时每 2 秒重试，授权后自动启动）
```

- 用户在设置里开关某个功能 → 宿主调用 `activate` / `deactivate`，不需要重启 App。
- 宿主维护每个功能的状态机：`disabled → needsPermission → running → failed`，统一显示在设置页上。

---

## 8. UI 结构

- **菜单栏图标**：常用命令、功能状态、打开设置、退出。
- **统一设置窗口**（`MAIOShell` 提供的壳）：
  - 通用：登录启动、外观、配置导入/导出
  - 快捷键：所有绑定的总表（按功能分组、搜索、冲突高亮、录制），这是 BetterTouchTool 式的核心页面
  - 系统快捷键：系统 🌐 快捷键一览、与 MAIO 的冲突、带备份的禁用与一键恢复（ADR-0005，实现在 `MAIOCore/SystemShortcuts/`）
  - 权限：所有权限的状态和一键跳转
  - 各功能：侧边栏每个功能一项，内容是 `feature.makeSettingsView()`
- **MAIOUI 设计系统**：浮动面板（`NSPanel` 封装）、HUD、快捷键录制器、设置表单行。所有功能复用这些组件，保证外观一致，也避免每个功能各写一套 NSPanel。

---

## 9. 并发、错误与日志

- **Swift 6 语言模式 + 严格并发检查**，所有警告视为错误。
- UI 和 Feature 协议都在 `@MainActor`；耗时工作（OCR、网络翻译、数据库）放在功能内部的 `actor` 或 `Task` 里。
- event tap 线程是实时路径：tap 本身只在 `MAIOCore/Input/` 中创建；功能的实时代码只能放在自己的 `Realtime/` 目录中，以 `RealtimeInputFilter` 的形式注册（§5.4）。
- 每个功能定义自己的 `Error` 枚举；命令失败统一由 CommandBus 捕获，记日志，必要时 HUD 提示。
- 日志：`os.Logger(subsystem: "app.maio", category: featureID)`，用 Console.app 按功能过滤。

---

## 10. 测试策略

| 层 | 测什么 | 怎么测 |
|---|---|---|
| `MAIOKit` | 值类型（KeyChord 解析与格式化、Binding 编解码） | Swift Testing 纯单测 |
| `MAIOCore` | 匹配器、绑定冲突、设置迁移、宿主故障隔离 | 单测；平台层用协议隔离 |
| `Feature*/Domain` | 业务逻辑（剪贴板去重、切换器排序、翻译结果解析） | 纯单测，不依赖 AppKit |
| `Feature*` 整体 | activate → 注册命令 → perform → 行为正确 | 用 `MAIOTesting.FakeFeatureContext` |
| 系统集成 | event tap、权限、截图 | 手动验证清单（`docs/manual-qa.md`），不追求自动化 |

---

## 11. 防"屎山"机制（针对 Agent 协作）

| 机制 | 防的是什么 |
|---|---|
| SPM target 依赖 | 功能互相 import、功能 import Core，编译直接失败 |
| `scripts/check-architecture.sh` | 二次校验依赖图、禁止的 import、禁止的 API（如 `UserDefaults.standard`、`CGEvent.tapCreate` 出现在 `MAIOCore/Input/` 之外）、`Realtime/` 目录中出现主线程 API |
| SwiftLint（文件 ≤ 400 行、函数 ≤ 60 行、禁止强制解包等） | 巨型文件、巨型函数 |
| SwiftFormat | 风格漂移导致的无意义 diff |
| `make new-feature NAME=xxx` 脚手架 | 每个功能结构一致，Agent 不必自己发明结构 |
| 每个功能一份 `README.md` | Agent 只读一个目录就能上手 |
| `make check` = 格式 + lint + 架构校验 + 测试 + 构建 | Agent 交付前必须全绿 |
| ADR（`docs/adr/`） | 架构决策有据可查，Agent 不会推翻前面的决定 |
| `docs/PROGRESS.md` | 新 session 的 Agent 能接上进度，不重复劳动、不推翻半成品 |
| `references/` 本地参考源码 | Agent 查参考实现时不用上网瞎搜，也不会照抄错误版本 |
| `CLAUDE.md` 守则 | 明确告诉 Agent 能做什么、不能做什么 |
| `MAIOKit` 变更需要 ADR | 地基保持稳定 |
| 第三方库白名单 | 依赖不失控 |

---

## 12. 技术选型

| 项 | 选择 | 理由 |
|---|---|---|
| 语言 | Swift 6.3，严格并发 | 原生、安全 |
| UI | SwiftUI 为主，AppKit 处理面板、菜单栏和窗口层级 | 浮动面板等场景 SwiftUI 力有不逮 |
| 最低系统 | macOS 26 | 自用，不背兼容包袱 |
| 工程 | XcodeGen（`project.yml`）+ 本地 SPM 包 | 避免 Agent 编辑 `.pbxproj` 产生冲突和损坏，见 ADR-0001 |
| 登录启动 | `SMAppService.mainApp` | 系统官方方案 |
| 测试 | Swift Testing | |
| 截图 | ScreenCaptureKit；OCR 用 Vision | |
| 签名 | 固定的本地开发证书 | 避免每次重新编译后 TCC 权限失效 |
| 第三方库 | 默认不引入；确有需要时发 ADR 并加入白名单（候选：GRDB 用于剪贴板历史） | |

---

## 13. 里程碑

| 阶段 | 交付 | 验收标准 |
|---|---|---|
| **M0 地基** | 工程骨架、MAIOKit 全部协议、FeatureHost、CommandBus、InputEngine（键盘 + 指针）、设置窗口壳、绑定编辑器、权限页、登录启动、`SystemActions` 功能、Fn 键验证 | `Fn+A` 能打开活动监视器；`make check` 全绿；ADR-0004 定稿 |
| **M1** | Scroll（鼠标反转、步长、平滑、按 App 例外） | 用它替换掉 Mos；验证指针实时过滤器 API 是否成立 |
| **M2** | Clipboard | 用它替换掉现有剪贴板工具 |
| **M3** | Switcher（Alt+Tab） | 用它替换掉现有切换工具；验证键盘会话 API |
| **M4** | Translate | 划词翻译 + 输入翻译 |
| **M5** | Screenshot | 区域截图、标注、贴图、OCR → 翻译（验证契约命令）、长截图、历史。详见 `docs/specs/M5-screenshot.md` |

`SystemActions` 放在 M0，是为了用一个最简单的真实功能把整套 Feature 协议跑通，先证明架构本身成立。
Scroll 紧接在 M1，是因为它是你每天都在用的工具，而且能尽早压测输入引擎中风险最高的实时路径。

---

## 14. 从参考项目学到的教训

参考源码放在 `references/`，清单与许可证见 `references/README.md`。

**vorssaint-utils**（功能取向和 MAIO 最接近，但我们不照它的结构来做）：

| 它的做法 | 问题 | MAIO 的对策 |
|---|---|---|
| 31 万行代码在一个 executable target 里 | 边界完全靠自觉 | 多 target，编译器强制边界（§2） |
| 单文件 5000+ 行，`AppDelegate` 2800+ 行 | 无法阅读，Agent 也读不全 | 文件 ≤ 400 行，App 壳只做组装 |
| 25 个文件各自创建 CGEventTap | tap 互相干扰，顺序不可控 | 唯一的 InputEngine + 分阶段过滤器（§5） |
| 全局 `Defaults.swift`（2800 行）集中所有设置项 | 每加一个功能都要改公共大文件 | 每个功能自带设置结构，按命名空间存储（§6） |
| 本地化字符串集中在几个 3000+ 行的大文件里 | 合并冲突、难以定位 | 每个功能目录自带字符串目录（String Catalog） |

可借鉴的部分：按需安装功能的思路（对应我们的功能开关）、权限按功能申请（对应 `requiredPermissions`）、`docs/PERMISSIONS.md` 和 `docs/SCROLL-ZOOM-TESTING.md` 这类手动测试清单。

**Mos**：滚动核心（`Mos/ScrollCore/`）职责拆分清晰——事件解析、过滤、插值、display link 发送、阶段管理各自一个文件，FeatureScroll 的内部划分可以直接参考这个结构。
