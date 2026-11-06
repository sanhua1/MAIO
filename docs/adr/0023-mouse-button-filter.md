# ADR-0023：输入引擎开放鼠标按键过滤器（中键、侧键）

- 状态：已采纳
- 日期：2026-11-06

## 背景
按键管理 P3（docs/specs/M8-keys.md K6）要把鼠标侧键（后退 / 前进）、中键改成组合键或 MAIO 命令，替代用户 Karabiner 里的
"后退键 → ⌘W、前进键 → ⌘Q"。原来的键会触发浏览器后退等，必须在到达 App 之前吞掉，event tap 只能在 `MAIOCore/Input/` 创建（ADR-0003），
现有的指针过滤器只处理滚轮。

## 决定
- MAIOKit 新增 `MouseButtonEvent`（按钮号：2 中键、3 后退、4 前进……，按下时的修饰键）和 `RealtimeButtonFilter`，
  `InputService.registerButtonFilter`。决定沿用按键过滤器的 `KeyFilterDecision`：`pass` / `consume` / `replace(KeyChord)`。
- 只把**按下**交给过滤器；按下被吞掉或改发的按钮，引擎自己吞掉对应的抬起。左右键（0、1）不交给过滤器。
- MAIOCore 新增 `ButtonTap`：会话层（`cgSessionEventTap`），只监听 otherMouseDown / otherMouseUp，**只在有过滤器时运行**，
  不影响移动、点击、滚轮的开销。MAIO 自己发出的合成事件不交给过滤器。
- 按注册顺序，第一个不是 `pass` 的结果生效（和按键过滤器一样）。

## 备选方案
- 扩展现有指针 tap 的 `PointerEventKind`：`PointerEvent` 是围绕滚轮设计的（`scrollY` 等字段），硬塞按钮会让滚轮过滤器都要判断类型。否决。
- 用 IOHIDManager 读鼠标按钮：只能看，吞不掉原来的"后退"。否决。
- 做成快捷键绑定的一种触发方式（CommandBinding）：绑定表只认 `KeyChord`，改动面更大；按键管理里"键 → 组合键 / 命令"已经有同样的界面。以后需要时再加。

## 后果
- MAIOKit 多一个协议和一个注册方法；`FakeInputService` 同步实现。
- 鼠标按钮事件会多经过一个 tap（只有启用了按键管理里的鼠标改键时才有）。
