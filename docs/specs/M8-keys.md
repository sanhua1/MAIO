# M8 按键管理（FeatureKeys）需求与设计

> 状态：需求已和用户确认（2026-11-06）。**P1、P2 已完成并经用户实测**（ADR-0022），P3 代码完成待实测（ADR-0023 鼠标按钮过滤器）。按第 6 节分阶段实施，每个阶段都交给用户实测。
> 背景：用户现在用 Karabiner-Elements 做改键，希望 MAIO 接管其中常用的部分，**但不要像 Karabiner 那么重、那么全**。
> 相关决策：ADR-0003（输入引擎，唯一的 event tap）、ADR-0004（Fn 键）、ADR-0022（两层改键）。MAIOKit 已经有键盘同步改写接口 `InputService.registerKeyFilter`（Finder 增强在用），P2 预计不用改 MAIOKit。

## 1. 用户的决定（原话要点）

- 改键分两级：**设备级**和**全局级**。
- **设备级**：识别出接着的键盘，针对这个键盘改。例：Mac 自带键盘从左到右改成 **⌘ ⌃ Fn ⌥**（出厂是 Fn ⌃ ⌥ ⌘）。只改接着的设备，**不需要"修饰键全局改"**。
- 用户自制的 Makey75 键盘固件原生就是 Mac 配列，**什么都不改**。
- **全局级**：对所有键盘生效。Caps 分层是全局的；其他组合键改键也放在全局。
- **Caps 是分层键，不是"Caps + 某键"的组合键**：打开分层后 Caps 原本的功能完全没有，**单按 Caps 什么都不发生**；按住 Caps 时整个键盘是另一层。
- 各个键盘的 Caps 变成**同一个值**，不要按键盘区分。
- **不要用 F 区**（包括 F13～F24）：有些高位 F 键是用户自己设置的。
- 层里的键**可以绑定 MAIO 命令**。
- 希望改键像 Karabiner 一样在很底层接管（能做到哪一步、做不到什么见 5.1）。

## 2. 用户现在的 Karabiner 配置（`~/.config/karabiner/karabiner.json`）

| 配置 | 内容 | M8 怎么处理 |
|---|---|---|
| 设备级：自带键盘（1452/835）、妙控键盘（1452/666） | fn→⌘、⌘→⌥、⌥→fn | P1 设备级修饰键，写进系统 |
| Caps 层 | 按住：W A S D = ↑ ← ↓ →，Q/E = PageUp/PageDown，X/C = ⌘← / ⌘→（行首 / 行尾）；单按 = Esc | P2 默认层用这一套，**单按改成什么都不发生**（用户的决定） |
| 全局 | Home → ⌘←，End → ⌘→ | P3 |
| 全局 | F23 → fn | P3 支持单键换单键；这条用户自己决定要不要 |
| 全局 | 鼠标后退键 → ⌘W，前进键 → ⌘Q | P3 |
| 设备 | 罗技鼠标 1133/50503 指针速度 ×1.4 | 不做（属于指针，以后放滚动模块） |
| 设备 | 雷蛇 5426/164 忽略 | 不需要（MAIO 不独占设备） |

## 3. 功能清单与验收标准

| # | 功能 | 验收标准 |
|---|---|---|
| K1 | 键盘列表 | 列出接着的键盘：名称、厂商 / 产品 ID、是否自带。插拔后 1 秒内刷新。Karabiner 的虚拟键盘不列出 |
| K2 | 设备级修饰键 | 选中一个键盘，Caps / ⌃ / ⌥ / ⌘ / 🌐(Fn) 每个都能改成另外几个之一或"无操作"，立即生效。**和系统设置"键盘 › 键盘快捷键 › 修饰键"是同一份设置**：两边改了都能互相看到；退出 MAIO、重启电脑、拔插后仍然生效。一键还原默认 |
| K3 | Caps 分层（全局） | 打开后，所有键盘的 Caps 都不再切换大写锁定（不亮灯、不变大写），单按什么都不发生。按住 Caps 时用"Caps 层"的映射；层里按 ⇧⌃⌥⌘ 会叠加到输出上（⇧+S = ⇧↓）；按住连发。松开 Caps 立即回到普通层。关掉分层或退出 MAIO 后 Caps 恢复原样 |
| K4 | 层的映射 | 层里每个键可以设成：一个键（W→↑）、一个组合键（X→⌘←）、一个 MAIO 命令（T→打开终端）。没设置的键照常输出（先按推荐做，见第 7 节）。默认值 = 用户现在的 Karabiner 配置 |
| K5 | 全局改键 | 单键 → 单键（例 F23→fn）；单键 → 组合键（Home→⌘←），按住连发 |
| K6 | 鼠标侧键 | 后退 / 前进 / 中键 → 组合键或 MAIO 命令 |
| K7 | Karabiner 提示 | 检测到 Karabiner 在运行时，页面顶部提示"Karabiner 会接管键盘，MAIO 的改键可能不生效，请先退出 Karabiner" |

## 4. 交互

设置里新增"按键管理"，分三页：

1. **键盘**（设备级）：左边是接着的键盘列表，右边是选中键盘的修饰键表（五行：Caps、⌃、⌥、⌘、🌐，每行一个下拉框），底部"还原默认"。没接着的键盘不列出（它的系统设置仍然保留，下次接上会显示）。
2. **Caps 分层**（全局）：总开关；键盘示意图或列表，列出层里每个键的映射，点一行修改（录一个键 / 组合键，或选 MAIO 命令）；"还原为默认层"。
3. **其他改键**（全局）：单键 → 单键、单键 → 组合键、鼠标侧键，每条一行，可以加、删、停用。

## 5. 技术设计

### 5.1 为什么做不到和 Karabiner 完全一样

Karabiner 独占每个实体键盘（需要 root 常驻进程），再从自己的 DriverKit 虚拟键盘发出改过的按键。
DriverKit 驱动要用苹果审批的 entitlement + Developer ID 签名；MAIO 是自签名证书（ADR-0016），装不了驱动，也做不了 root 常驻进程。
借用已装好的 Karabiner 驱动同样需要 root，而且等于要求用户装 Karabiner。

所以 MAIO 用两层：

| 层 | 机制 | 做什么 | 特点 |
|---|---|---|---|
| HID 层 | IOHIDEventSystemClient 给键盘服务设属性：修饰键用系统设置同一套（`HIDKeyboardModifierMappingPairs` + ByHost 偏好，P1 实验确认键名），其他单键用 `UserKeyMapping`（等同 `hidutil`） | 设备级修饰键、全局单键换单键、把 Caps 换成分层键 | 在所有 event tap 之前；密码框里也生效；无延迟 |
| 拦截层 | 现有的 HID 级 event tap（ADR-0003，MAIO 是全系统第一个键盘 tap），新增**键盘同步改写**接口 | 分层、单键换组合键、绑定命令 | 需要判断逻辑的都在这里 |

和 Karabiner 相比的差别（P2 实测后补充）：
- 密码框、终端"安全键盘输入"打开时，系统不把按键交给任何 event tap：这时分层不工作，Caps 按了没反应（HID 层已经换掉），字母照常。
- 层里发出的是合成按键，极少数游戏 / 虚拟机会忽略。
- event tap 分不出按键来自哪个键盘，所以分层和组合键改键只做全局（用户也是这么要求的）。

### 5.2 Caps 为什么还要在 HID 层换成另一个值

macOS 对 Caps Lock 有特殊处理：按下时系统先切换大写锁定状态和指示灯（在 event tap 之前），
event tap 只能收到"锁定状态变了"的 flagsChanged，收不到可靠的按下 / 松开，也拦不住大写锁定生效。
所以没有驱动时，必须先在 HID 层把 Caps 换成一个普通键，event tap 才能看到完整的按下 / 松开，并把它吞掉当分层键。

这个值对所有键盘都一样（全局 `UserKeyMapping`），而且**不用 F 区**（用户的决定）。要求：
1. macOS 会为它产生正常的 keyDown / keyUp（有虚拟键码），event tap 能看到；
2. MAIO 没有吞掉它时（安全输入、MAIO 崩溃）没有任何效果：不打字、不切输入法、不触发系统功能；
3. 用户的键盘不会发出它。

**P2 实际做法（比下面的候选更好）**：Caps 在 HID 层设成"无操作"（`0x700000000`，不发出任何键），按下 / 松开从 IOHIDManager 读键盘原始输入（不受 HID 映射影响）。不借用任何键值。下面的候选没有再试。

原来的候选：HID 键盘页里 macOS 一般用不到的键，例如 Execute（0x74）、Help（0x75）、Menu（0x76）、Select（0x77）、Stop（0x78）、International / LANG 系列（0x87～0x94，要排除会切换日文输入法的 LANG1/LANG2）。
MAIO 正常退出时删掉这条映射；崩溃时映射留着（Caps 按了没反应），下次启动 MAIO 时重新设置，或重启电脑后清掉。

### 5.3 模块结构（`Packages/MAIO/Sources/FeatureKeys/`）

- `Domain/`：`KeyboardDevice`（ID、名称、是否自带）、`ModifierMapping`（修饰键表 ↔ HID usage 对）、`LayerMap`（层的映射、默认层）、`RemapRule`（全局改键）、`HIDUsage`（usage ↔ 显示名 ↔ 虚拟键码）
- `Infrastructure/`：`HIDKeyboards`（列设备、插拔通知）、`ModifierMappingStore`（读写系统的修饰键设置）、`UserKeyMapping`（全局单键映射，含 Caps 分层键）、`KarabinerDetector`
- `Realtime/`：层的按键改写（tap 线程上同步执行，规则同 ADR-0003 的 `RealtimeInputFilter`）
- `UI/`：三个设置页

### 5.3a P1 实验记录（2026-11-06，程序在 `/tmp/maio-exp/keys/src`）

- ① 系统设置改修饰键（自带键盘，🌐→⌘、⌥→🌐、⌘→⌥）写两处：
  - 偏好：`defaults -currentHost` 的全局域（`kCFPreferencesAnyApplication` + `CurrentUser` + `CurrentHost`），键 `com.apple.keyboard.modifiermapping.<VendorID>-<ProductID>-0`，值是 `[{HIDKeyboardModifierMappingSrc, HIDKeyboardModifierMappingDst}]`，整数 = `(usagePage << 32) | usage`。
  - 键盘服务属性 `HIDKeyboardModifierMappingPairs`（同样的数组），立即生效。
  - 一个修饰键写左右两条：⌘ = 0x7000000E3 / 0x7000000E7，⌥ = 0xE2 / 0xE6，⌃ = 0xE0 / 0xE4，⇧ = 0xE1 / 0xE5；🌐 作为**来源**写两条（`0xFF0100000003` → 左、`0xFF00000003` → 右），作为**目标**写 `0xFF00000003`。
- ② 写服务属性要用 `IOHIDEventSystemClientCreateWithType`（导出但不在公开头文件，dlsym 取）：type 0（admin）拿不到服务；**type 1（monitor）可以读写，不需要 root**；type 4（simple，即 `IOHIDEventSystemClientCreateSimpleClient`）读不到也写不了；`hidutil property --set` 这个属性也不生效。
- 系统设置的键盘面板（`KeyboardSettings.appex`）用的就是 `CreateWithType` + `IOHIDServiceClientSetProperty` + `CFPreferencesSetValue`。
- ② 用户实测（P1 设置页）：MAIO 改 Caps→Esc 立即生效，重新打开系统设置能看到；系统设置改回去，MAIO 重新打开设置页也能看到。
- ③ 只写偏好（不设属性）给 Makey75 写一条无效果的映射，拔插后键盘服务上出现了这条映射：**键盘重新接上时系统自己从偏好读出来应用**，MAIO 不用监听插拔。重启后是否保留没单独测（和系统设置是同一套机制）。测试映射已删除。

### 5.4 权限

辅助功能、输入监控（MAIO 已经有）。HID 属性写入不需要 root（P1 实验确认）。

## 6. 分阶段实施

| 阶段 | 内容 | 先做的实验 |
|---|---|---|
| P1 | K1 键盘列表、K2 设备级修饰键、K7 Karabiner 提示。不涉及 event tap | ① 在系统设置里改一个修饰键，对比改前改后，确认它存在哪（ByHost 键名、值的格式、Fn/🌐 的 usage）；② MAIO 写入后系统设置能不能看到、立即生效；③ 拔插、重启后还在不在。**实测时要先退出 Karabiner**（它独占键盘时，系统的修饰键设置对实体键盘不起作用） |
| P2 | K3 Caps 分层（用现有的 `registerKeyFilter`；不够用再写 ADR 改 MAIOKit）、K4 层的映射（含 MAIO 命令） | ① 5.2 的候选键逐个验证；② 安全输入时的表现；③ 层里连发、叠加修饰键；④ 全局 `UserKeyMapping` 对新接上的键盘是否自动生效 |
| P3 | K5 全局改键、K6 鼠标侧键 | 单键换 fn（F23→fn）在第三方键盘上是否有效 |

## 7. 待确认

- 层里没设置的键：用户没有回答，先按推荐做"照常输出"（和 Karabiner 一样），P2 实测时再问。
- 迁移完成后用户退出 Karabiner；MAIO 不去改 Karabiner 的配置。
