# 鼠标滚动（`scroll`）

替换 Mos：反转鼠标滚轮方向、平滑滚动、调整滚动跨度，并可按 App 设置例外。按住 ⌘ 拨滚轮可以像触控板双指捏合一样缩放。**触控板和妙控鼠标不受影响。**

## 工作方式

```
滚轮事件 → 输入引擎指针 tap（注释会话层）→ ScrollInputFilter（Realtime/，tap 线程）
             │ ScrollPlanner（Domain/，纯函数）决定：放行 / 反转后放行 / 交给平滑
             └→ SmoothScrollAnimator（Realtime/，独立队列，按屏幕刷新率）
                   SmoothScroller（Domain/）逐帧计算位移 → context.input.poster 发出像素滚动事件
```

| 事件来源 | 处理 |
|---|---|
| 触控板、妙控鼠标（有手势或惯性阶段） | 不碰 |
| MAIO 自己发出的事件 | 不碰 |
| 远程控制软件注入的事件（屏幕共享、UU 远程、ToDesk、向日葵等，ADR-0013） | 不碰（控制端已处理过方向和平滑；输入引擎直接放行） |
| 已经是连续滚动的滚轮（Logitech 平滑滚动） | 只反转，不再平滑 |
| 普通滚轮 | 反转 + 平滑 |
| 按住缩放修饰键（默认 ⌘） | 吞掉，变成触控板捏合缩放（见下） |
| 按住其他 ⌘ / ⌃ / ⌥ | 只反转，不平滑（保证 App 自己的修饰键 + 滚轮功能正常） |

App 例外按**鼠标所指的 App**判断（滚动事件的目标进程），而不是前台 App。

## 滚轮缩放（ADR-0015）

按住修饰键（默认 ⌘）拨滚轮 → `ZoomPlanner`（Domain/）算出缩放量（每像素 0.005 × 速度，按反转后的方向，往前拨放大）→ `PinchZoomer`（Realtime/）发出一次完整的捏合手势：第一格 began，之后按 120Hz 逐帧 changed（`ZoomEaser` 把每格分摊到后面几帧），松开修饰键或停下 0.5 秒后 ended。鼠标在 MAIO 自己的窗口上时不缩放（按滚动事件的目标 App 判断），贴图的 ⌘ + 滚轮仍然调透明度。事件由 `context.input.poster` 的 `.magnify` 发出，不带修饰键。

## 命令

| 命令 | 说明 |
|---|---|
| `scroll.toggleReverse` | 开关鼠标滚动反转 |
| `scroll.toggleSmooth` | 开关平滑滚动 |

## 设置项（默认值与 Mos 相同）

| 字段 | 默认 | 说明 |
|---|---|---|
| `reverseVertical` / `reverseHorizontal` | `true` | 反转鼠标滚动（系统开着"自然滚动"时，让鼠标恢复传统方向） |
| `smoothEnabled` / `smoothVertical` / `smoothHorizontal` | `true` | 平滑滚动 |
| `step` | 33.6 | 每格滚轮最少滚动的像素 |
| `speed` | 2.7 | 位移倍率 |
| `duration` | 4.35 | 平滑时长（1–5） |
| `shiftToHorizontal` | `true` | 按住 ⇧ 横向滚动 |
| `zoomEnabled` | `true` | 修饰键 + 滚轮缩放 |
| `zoomModifier` | `command` | 缩放修饰键：`command` / `option` / `control` |
| `zoomSpeed` | 1.0 | 缩放速度（0.3–3），1.0 约为每格 5% |
| `zoomReversed` | `false` | 反转缩放方向 |
| `exceptions` | `[]` | App 例外：关闭平滑 / 关闭反转 |

## 权限

辅助功能（输入引擎统一申请）。

## 参考

LinearMouse（MIT）：手势事件的字段号和捏合的发送时机，见 `references/LinearMouse/Modules/GestureKit/`。

Mos（CC BY-NC 4.0，只借鉴思路、独立实现）：
- `references/Mos/Mos/ScrollCore/ScrollCore.swift`：反转 / 平滑决策流程
- `references/Mos/Mos/ScrollCore/ScrollPoster.swift`、`ScrollFilter.swift`：插值与滤波
- `references/Mos/Mos/Utils/Constants.swift`：默认参数、持续时间换算公式

与 Mos 的差异：用独立队列上的高精度定时器代替 CVDisplayLink；按帧率换算插值比例，60Hz 和 120Hz 手感一致。

## 已知限制

- 缩放用的是私有的手势事件字段（WebKit 测试代码里公开过），系统升级后可能失效。不支持捏合的 App（例如终端）里没有反应。
- 缩放打开时，App 自己的"⌘ + 滚轮"功能会被替换；可以换成 ⌥ / ⌃ 或关掉。

- 没有模拟触控板的手势阶段（Mos 的"模拟触控板"选项）。个别 App 依赖手势阶段做回弹效果时，平滑滚动看起来会像普通像素滚动。
- 帧率在功能启动时确定；运行中接入刷新率不同的显示器，需要在设置中关闭再打开本功能。
