# ADR-0028：输入引擎开放媒体键过滤器；功能可以往菜单栏菜单放视图

- 状态：已采纳
- 日期：2026-11-21

## 背景
外接显示器功能（docs/specs/M9-display.md）要用 Mac 的音量键、亮度键调外接显示器（DDC/CI）：
- 声音从显示器出来（DP / HDMI 音频）时系统调不了音量，按音量键只弹"无法调节"；外接显示器的亮度系统也调不了。
- 这些键必须在到达系统之前吞掉，否则系统照样弹提示。event tap 只能在 `MAIOCore/Input/` 创建（ADR-0003），
  现有的按键过滤器只收 keyDown / flagsChanged，收不到媒体键（`NX_SYSDEFINED` 事件）。
- 用户要求菜单栏菜单里不再列功能开关，改为在接了外接显示器时显示亮度滑块。菜单在 MAIOShell，功能不能被 Shell 以外的地方直接引用。

## 决定
1. MAIOKit 新增 `MediaKey`（音量加 / 减、静音、亮度加 / 减）、`MediaKeyEvent`（键、是否重复、⌃⌥⇧⌘）、`RealtimeMediaKeyFilter`，
   `InputService.registerMediaKeyFilter`。决定沿用 `FilterDecision`（`pass` / `consume`）：媒体键没有"改发别的键"的需求。
2. `KeyboardTap` 的 mask 加上 `NX_SYSDEFINED`（14）。子类型 8 的事件按 `data1` 解析（`MediaKeyRouter`）；
   苹果键盘的亮度键是 keyDown 144 / 145，也当成亮度键交给过滤器，没被吞掉时照常走快捷键流水线。
   只把按下（包括重复）交给过滤器；按下被吞掉时引擎自己吞掉对应的抬起。**没有媒体键过滤器时完全不解析**，不增加开销。
3. 媒体键不受"远程桌面让出快捷键"（ADR-0027）影响：它调的是本机硬件。
4. `Feature` 协议新增可选的 `makeMenuBarView() -> AnyView?`（默认 nil）。Shell 每次打开菜单时向运行中的功能要视图，
   按功能目录顺序放在菜单最上面（固定宽度 280），返回 nil 就不显示。菜单里不再列出功能开关（开关在设置里）。

## 备选方案
- 媒体键做成快捷键绑定（`KeyChord` 加媒体键）：要不要接管取决于"当前声音输出系统能不能调"、"鼠标在哪块屏幕上"，
  只能在 tap 线程上实时判断，绑定表做不到"有时放行"。否决。
- 用系统的 `OSDManager`（OSD.framework）弹浮窗：macOS 27 上调用不报错但不显示（实测）。改为功能自己画。
- 在功能里自己监听 `NX_SYSDEFINED`：违反"event tap 只在 MAIOCore/Input"。否决。
- 菜单视图用 AppKit 的 `NSMenuItem`：MAIOKit 不能 import AppKit。用 SwiftUI 的 `AnyView`，和 `makeSettingsView` 一致。

## 后果
- MAIOKit 多一个协议、一个注册方法、`Feature` 多一个可选方法；`FakeInputService` 同步实现。
- 键盘 tap 多收一种事件（系统定义事件，频率很低）。
