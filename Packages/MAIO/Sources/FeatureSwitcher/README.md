# 窗口切换（`switcher`）

类似 Windows 的 Alt+Tab：按住修饰键，再按主键在窗口间切换，松开修饰键即切过去。**触发键可自定义**：在本功能设置页顶部直接录制（或在「快捷键」页把任意组合键绑定到 `switcher.show`）（默认 ⌥⇥；想替换系统的 App 切换器就绑 ⌘⇥）。

## 工作方式

```
快捷键 ⌥⇥ → switcher.show（命令来源携带触发组合键，ADR-0007）
  → SwitcherController：开始键盘会话（之后所有按键交给切换器，直到结束）
  → WindowCatalog（后台）：AX 枚举各 App 窗口 + CGWindowList 叠放顺序
  → WindowOrdering（Domain）：排序、过滤 → SwitcherSession（Domain）：按键状态机
  → 按下即开始截缩略图（跨次缓存，避免先闪图标）→ 延迟 showDelay 后显示面板（矩形网格，SwitcherLayout）
  → 松开修饰键 → WindowActions.focus（SkyLight + 检查重试）
```

| 按键（修饰键按住时） | 作用 |
|---|---|
| 触发主键 / ⇥ / → | 下一个 |
| ⇧⇥ / ← | 上一个 |
| ↑ / ↓ | 网格中上下移动（同列循环） |
| 松开修饰键、Return、空格 | 切换到选中项 |
| 鼠标悬停 | 只做浅色高亮，**不改变选中项**（松手切换的仍是键盘选中的那个） |
| 鼠标点击 | 切换到点击的那一项 |
| Esc | 取消 |
| W / M / H / Q | 关闭窗口 / 最小化 / 隐藏 App / 退出 App |

**防卡死**：键盘会话期间所有按键都被切换器接管，所以有两道兜底——每 120ms 直接查询修饰键是否已松开（"松开"事件丢失时自动确认）；会话最长 60 秒，超时自动取消。

## 命令

| 命令 | 默认快捷键 | 说明 |
|---|---|---|
| `switcher.show` | ⌥⇥ | 从上一个窗口开始 |
| `switcher.showReverse` | ⌥⇧⇥ | 从最后一个窗口开始 |

从菜单或 URL 调用时没有"按住的修饰键"，用 Return / Esc / 点击结束。

## 设置项

| 字段 | 默认 | 说明 |
|---|---|---|
| `showDelay` | 0.1 秒 | 在这之前松手直接切换，不闪面板 |
| `showThumbnails` | `true` | 需要"屏幕与系统录音"权限，否则显示图标 |
| `showMinimizedWindows` / `showHiddenApps` | `true` | |
| `showAppsWithoutWindows` | `false` | |
| `oneItemPerApp` | `false` | 每个 App 一项，类似系统 ⌘⇥ |
| `excludedBundleIDs` | `[]` | 不显示的 App |

## 权限

- 辅助功能（必需）：枚举窗口、提升窗口、关闭 / 最小化
- 屏幕与系统录音（可选）：缩略图

## 参考

alt-tab-macos（GPL-3.0，只借鉴思路、独立实现）：
- `src/switcher/state/WindowAdmissionResolver.swift`：哪些窗口算"可切换"
- `src/switcher/state/Window.swift`：切换到具体窗口的流程（私有 API 方案，见 ADR-0008 备选）
- `src/events/WindowCaptureEvents.swift`：macOS 26 用 ScreenCaptureKit 截缩略图
- `src/App.swift`：延迟显示面板、快速按一下直接切换

## 已知限制

- **只显示当前桌面（Space）的窗口**：`kAXWindows` 不返回其他桌面的窗口。alt-tab-macos 用私有 API 实现了跨桌面，代价高，暂不做。
- App 暂时不响应辅助功能查询（刚启动约 1 秒内、正忙；实测「预览」刚打开文件时会这样）：用屏幕窗口列表（CGWindowList）顶替它在屏幕上的窗口，
  切换时再按窗口 ID 补查辅助功能元素，仍查不到就只用 SkyLight 切换。这种情况下它的最小化窗口不会出现。
- 排序用屏幕叠放顺序近似"最近使用"；不在屏幕上的窗口按 App 最近使用顺序排列。
- 切换到具体窗口使用 SkyLight 私有函数（ADR-0008 修订），并在 150ms 后检查、必要时重试。排查问题时看日志：
  `/usr/bin/log show --last 10m --predicate 'subsystem == "app.maio" AND category == "switcher"' --info`
