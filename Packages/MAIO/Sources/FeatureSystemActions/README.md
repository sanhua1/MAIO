# 系统动作（`system`）

把快捷键绑定到通用动作。这是 MAIO 的第一个功能，也是整套 Feature 协议的最小示例。

## 命令

| 命令 | 参数 | 说明 |
|---|---|---|
| `system.openApp` | `app`：bundle ID 或 .app 路径 | 打开 App，已运行则切到前台 |
| `system.openURL` | `url`：网址或本地路径 | 用默认程序打开 |
| `system.runShell` | `script`，`showOutput`（可选） | `/bin/zsh -lc` 后台执行，60 秒超时 |
| `system.runAppleScript` | `source` | 通过 `osascript` 执行 |
| `system.runShortcut` | `name` | 运行"快捷指令" |
| `system.sendKeys` | `keys`：如 `cmd+shift+4` | 键位重映射 |

## 出厂快捷键

| 快捷键 | 动作 |
|---|---|
| `fn+a` | 打开活动监视器（M0 验收用例） |

## 设置项 / 权限

无设置项。`sendKeys` 依赖输入引擎（辅助功能权限，由宿主统一申请）。

## 已知限制

- Shell 命令在登录 shell 中运行，会加载 `~/.zprofile`，但不加载交互式配置。
- 运行 AppleScript 控制其他 App 时，系统会针对 MAIO 弹出"自动化"授权。
