# ADR-0015：修饰键 + 滚轮模拟触控板捏合缩放，`SyntheticEvent` 新增 `.magnify`

- 状态：已采纳
- 日期：2026-11-03
- 关联：ADR-0006（指针事件）、FeatureScroll

## 背景
用户希望用鼠标看图片、网页时，也能像触控板双指捏合一样缩放：按住一个键（默认 ⌘）再拨滚轮。

可选做法：
1. 发 ⌘+ / ⌘− 按键：每个 App 的缩放快捷键不同，一跳一跳，看图软件、地图往往不认。
2. **发触控板的捏合手势事件**：App 收到的就是 `NSEvent.magnify`，和真触控板一样平滑缩放，预览、Safari、Chrome、地图、Figma 都支持。LinearMouse（MIT）就是这样做的。

## 决定
- 采用做法 2。手势事件是 `NSEventTypeGesture`（29），用私有字段描述：110 = HID 类型（8 = 缩放），113 = 缩放量，132 = 手势阶段（began 1 / changed 2 / ended 4）。字段号来自 WebKit 的 `CoreGraphicsTestSPI.h`，参考 `references/LinearMouse/Modules/GestureKit/`。
- **修改 MAIOKit**：`SyntheticEvent` 新增 `case magnify(phase: ScrollPhase, magnification: Double)`。功能不能自己创建和发送 CGEvent（只有 MAIOCore 能），所以必须通过 `SyntheticEventPoster`。手势阶段复用已有的 `ScrollPhase`，不另起类型。
- 发出的手势事件**不带修饰键**：用户按 ⌘ 只是为了触发缩放。
- 一次捏合 = began → 若干 changed → ended。ended 的时机：松开修饰键（定时查 `CGEventSource.flagsState`），或 0.5 秒没有新滚动。每格滚轮的缩放量分摊到后面几帧发出，缩放是连续的。
- 方向按"反转后"的滚动方向算：往前拨滚轮放大，不受系统自然滚动设置影响；另有"反转缩放方向"开关。

- 鼠标在 MAIO 自己的窗口上（按滚动事件的目标进程判断）时不缩放：贴图的 ⌘ + 滚轮是调透明度，用户要保留。

## 后果
- 私有字段，系统升级后可能失效；失效时只是不缩放，不影响滚动。
- 打开后，App 自己的"⌘ + 滚轮"功能被替换。可以把修饰键换成 ⌥ / ⌃，或关掉。
