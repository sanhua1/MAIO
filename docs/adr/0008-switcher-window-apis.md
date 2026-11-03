# ADR-0008：窗口切换器的系统接口选择

- 状态：已采纳；2026-11-02 修订：启用备选方案 1（见下方「修订」）
- 日期：2026-11-02
- 关联：M3 FeatureSwitcher；参考 alt-tab-macos（`references/alt-tab-macos`）

## 背景
窗口切换需要：列出窗口、按最近使用排序、切换到具体窗口、截缩略图。
alt-tab-macos 为了覆盖所有边角情况，大量使用 SkyLight 私有 API（跨桌面枚举、`_SLPSSetFrontProcessWithOptions` + 伪造事件记录设置键盘焦点、远程 AX 令牌暴力枚举等），并且要跟着每个 macOS 版本修补（例如 macOS 14.7.4 起事件记录必须 0x100 字节，否则 WindowServer 崩溃）。

## 决定（MVP）
- **枚举**：每个普通 App 用 AX `kAXWindows`，按角色 / 子角色 / 尺寸过滤；用 `_AXUIElementGetWindow` 映射到 CGWindowID。只覆盖**当前桌面**。
- **排序**：`CGWindowListCopyWindowInfo(.optionOnScreenOnly)` 的叠放顺序（前面的就是最近用过的）；不在屏幕上的窗口按 App 激活历史排序。
- **切换**：只用公开 API——取消最小化 / 隐藏 → AX `kAXMain` + `kAXRaise` → `NSRunningApplication.activate()` → 80ms 后再提升一次。
  实测 macOS 26.5 上后台进程调用 `activate()` 能成功切换前台 App。
- **缩略图**：ScreenCaptureKit（`SCScreenshotManager.captureImage`），只在面板显示时截取；没有屏幕录制权限时显示图标。
- **唯一的私有函数**：`_AXUIElementGetWindow`（通过 `@_silgen_name` 声明），业界通用，十多年稳定。

## 备选方案（遇到问题时按需引入）
1. 焦点不可靠（切换后键盘焦点在错误的窗口）：引入 `_SLPSSetFrontProcessWithOptions(psn, wid, 0x200)` + `SLPSPostEventRecordTo`（alt-tab-macos 的做法，注意 0x100 字节缓冲区）。
2. 需要跨桌面：`CGSCopyManagedDisplaySpaces` + `CGSCopyWindowsWithOptionsAndTags`。
3. 需要更准确的最近使用顺序：为每个 App 注册 `kAXFocusedWindowChangedNotification` 观察者，维护焦点历史。

## 修订（2026-11-02）：启用备选方案 1
用户实测：切到 QQ 后，QQ 窗口停在 Otty 下面（偶发，目标不固定）。与 alt-tab-macos 注释描述的 macOS 26 行为一致。
- 切换改为：SkyLight `_SLPSSetFrontProcessWithOptions(psn, wid, 0x200)` + 事件记录让窗口获得键盘焦点 + AX 提升。
  实现在 `Infrastructure/SkyLightFocus.swift`，全部 dlsym 动态加载，缺失时退回公开 API。
- 切换后 150ms 检查目标是否在最上层，不在就重试，最多 2 次。
- 每次切换写日志（`subsystem == "app.maio" AND category == "switcher"`）：成功 / 重试 / 失败及挡住它的窗口。
- 验证：模拟按键连续切换 5 次（含按住连按显示面板），全部一次成功。

## 后果
- 实现简单、私有 API 风险小；代价是暂不支持其他桌面的窗口。
