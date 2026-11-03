# ADR-0011：截图流程（先冻结画面，再框选）

- 状态：已采纳（实现时可以根据 P1 的实验结果修订细节）
- 日期：2026-11-03

## 背景

M5 要替代 PixPin，对截图有四个要求：

- 从按下快捷键到出现遮罩要快（目标 ≤ 150 ms）；
- 打开的菜单、悬浮提示也要能截进去；
- 支持多显示器和 Retina；
- 能自动识别鼠标下面的窗口和控件。

需求详见 `docs/specs/M5-screenshot.md`。

## 决定

1. **先截图，再显示遮罩**。按下快捷键后，**在激活 MAIO 之前**截取所有显示器，遮罩上显示这些静态图。框选、标注、取色都基于这份冻结画面，最后从原图裁剪输出。
2. **截图接口按顺序尝试**：
   - macOS 26 的 `SCScreenshotManager.captureScreenshot(rect:configuration:)`，按显示器矩形截图，不需要 `SCShareableContent`；
   - 失败时用 `SCShareableContent` + `SCScreenshotManager.captureImage`。
   - 不使用已弃用的 `CGWindowListCreateImage`。
3. **每个显示器一个遮罩面板**：
   - 无边框，层级 `.screenSaver`，所有桌面空间可见，全屏 App 上方也可见；
   - 关闭出现动画，可以成为 key window；
   - 启动时预先创建并复用；空闲时 `ignoresMouseEvents = true`。
4. **窗口识别**：冻结的同时读取 `CGWindowListCopyWindowInfo`，之后鼠标移动只查这份列表。
   - 按 MAIO 的 PID 排除自己的窗口（pinlume 按名字过滤，有 bug）；
   - 排除层级为负、透明度接近 0、尺寸过小的窗口。
5. **控件识别**：在鼠标下那个 App 的元素上调用 `AXUIElementCopyElementAtPosition`，查询要节流并缓存。**先做实验验证**，不可行时只做窗口识别，并向用户说明。
6. 遮罩和画布用 AppKit 自己绘制；工具栏等界面用 SwiftUI。

## 备选方案

- **先框选、后截图**（系统 ⌘⇧4 的方式）：截不到会自动关闭的菜单；框选时看到的是实时画面，和最终结果可能不一致。
- **用 ScreenCaptureKit 视频流保持实时画面**：开销大，而且冻结画面正是我们想要的效果。
- **控件识别用系统级的辅助功能命中测试**：遮罩在最上层，会命中 MAIO 自己的窗口。

## 后果

- 冻结画面要占内存（多屏 5K 约 100 MB），截图结束后要立即释放。
- 截图期间屏幕上的动画是静止的，这是预期效果。
- 需要"屏幕与系统录音"权限。`CGPreflightScreenCaptureAccess()` 的结果在进程整个生命周期内不会更新，授权后要提示用户重启 MAIO。

## P1 实验结果（2026-11-03，M1 Pro + 一台 5K 显示器，缩放后 2560×1440 pt）

实验工具：`/tmp/maio-exp/capbench.swift`、`capcheck.swift`、`axprobe.swift`。

**截图接口**（截整个屏幕，5120×2880 px）：

| 接口 | 第一次 | 之后 |
|---|---|---|
| `captureScreenshot(rect:configuration:)` | 138 ms | 75 ms |
| `captureImage(in:)`（macOS 15.2） | 75 ms | 50 ms |
| `SCShareableContent` + `captureImage(contentFilter:)` | 270 ms | 130 ms（其中查询 40 ms） |
| `CGWindowListCopyWindowInfo` | | 1 ms |

- 选用 `captureScreenshot(rect:)`：可以设置 `showsCursor = false`；`captureImage(in:)` 不能配置，冻结画面里可能带上鼠标指针。
- 第一次调用慢约 60 ms，功能启用时先截一张 1×1 的图预热。
- 返回图片使用显示器自己的色彩空间（ICC），裁剪输出时保留这个色彩空间。
- 还没有在多显示器上验证（用户只有一台显示器）。代码按每个显示器单独截图，各自计算缩放比例。

**控件识别（第 5 条的实验）通过**：

- 在 `.screenSaver` 层放一个接收鼠标的全屏透明窗口后：
  - 系统级命中测试命中的是遮罩自己（如预期）；
  - 对目标 App 的元素调用 `AXUIElementCopyElementAtPosition`，仍然返回 App 里正确的控件。单次通常 0.4～0.9 ms，偶尔约 20 ms，所以放到后台串行执行，只保留最新一次查询。
- **窗口列表要排除程序坞**：程序坞有一个覆盖整个屏幕的透明窗口（layer 20）。不排除的话，任何位置都会命中程序坞。另外要排除 Window Server 的窗口（鼠标指针等）。
