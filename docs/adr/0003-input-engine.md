# ADR-0003：键盘与指针输入由唯一的 InputEngine 统一接管

- 状态：已采纳
- 日期：2026-11-02（同日修订：从"快捷键引擎"扩展为"输入引擎"，纳入滚轮处理）

## 背景
- 快捷键需要支持 ⌘ ⌃ ⌥ ⇧ Fn 任意组合、覆盖系统快捷键（如 ⌘Tab）、按住修饰键的持续会话（Alt+Tab）。`RegisterEventHotKey` 不支持 Fn，也无法覆盖系统快捷键。
- 滚动功能（鼠标反转、步长、平滑滚动）必须在事件到达 App 之前同步修改或吞掉滚轮事件。
- 参考项目 vorssaint-utils 在 25 个文件里各自创建 CGEventTap，导致顺序和相互干扰都不可控。

## 决定
- 只有 `MAIOCore/Input/` 能创建 CGEventTap：一个键盘 tap、一个指针 tap，各自运行在独立线程上。
- 键盘：快捷键匹配使用不可变绑定快照做 O(1) 查找，命中后异步回主线程执行命令；功能需要原始按键时，通过 `InputService.beginKeyboardSession` 获取。
- 指针：功能通过 `InputService.registerFilter` 注册 `RealtimeInputFilter`，在 tap 线程上同步执行，按固定阶段（observe → transform → smooth）排序。
- 合成事件只能通过 `InputService.post` 发出，由引擎统一打标记，防止自己处理自己发出的事件。
- 需要"辅助功能"和"输入监控"权限。

## 备选方案
- RegisterEventHotKey / KeyboardShortcuts 库：不支持 Fn，也无法覆盖系统快捷键。
- 每个功能各自创建 tap：即 vorssaint-utils 的做法，否决。
- 键盘和指针共用一个 tap：高频的滚轮事件会拖慢快捷键响应，否决。
- 滚轮处理也走异步命令模型：无法同步修改事件，不可行。

## 后果
- tap 回调必须极快，否则会被系统禁用，需要实现自动恢复。
- `RealtimeInputFilter` 是一个受约束的特权扩展点：实时代码必须放在功能的 `Realtime/` 目录，由架构校验脚本检查。
- Fn / 🌐 键的系统快捷键可能拦截不了，见 ADR-0004（M0 验证后定稿）。
