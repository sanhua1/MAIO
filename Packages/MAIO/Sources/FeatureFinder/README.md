# Finder 增强（`finder`）

让 Finder 用起来像 Windows 资源管理器。**不注入 Finder**（ADR-0017）。功能默认关闭，在设置 › Finder 增强 里打开。
设置页分三页：

1. **快捷键**：MAIO 补充的动作表（可开关、可改键）、速查面板、Finder 原生快捷键（展示和重设）。所有快捷键冲突实时提示。
2. **右键菜单**：Finder Sync 扩展（ADR-0019）的开关、每一项的开关、新建模板。
3. **隐藏设置**：直接改 Finder 自己的配置，带备份和一键还原。

## 工作方式

```
按键 → 输入引擎键盘 tap → FinderKeyFilter（Realtime/，RealtimeKeyFilter，ADR-0017）
         │ FinderKeymap（Domain/）：不在 Finder / 正在输入文字 → 放行；否则按动作表改发组合键或交给主线程
         └→ FinderEnhancer（主线程）：剪切确认、新建文件、打开终端、速查面板
FinderMenuStore：用辅助功能接口读 Finder 菜单 → 改键目标跟着 Finder 当前的快捷键走（用户改过"返回"的快捷键，⌫ 也能跟上）
FinderFocusMonitor：AXObserver + 0.5 秒轮询 → 焦点在文本框（AXTextField/AXSearchField…）= 正在输入
右键菜单：FinderSync/（扩展，沙盒）读 data/finder/context-menu.json → 点击 → maio://run/finder.contextMenu → 主程序执行
```

## 动作表（`Domain/FinderActions.swift`）

| 动作 | 默认快捷键 | 做什么 |
|---|---|---|
| 打开 | ⏎（含小键盘 Enter） | 发 Finder「文件 › 打开」；按住不连续打开 |
| 重命名 | F2 | 发 ⏎ |
| 移到废纸篓 | ⌦ | 发「文件 › 移到废纸篓」 |
| 后退 | ⌫ | 发「前往 › 返回」 |
| 前进 | 不设 | 发「前往 › 前进」（⌥→ 是列表视图的"展开全部"，所以默认不设） |
| 上一级文件夹 | ⌥↑ | 发「前往 › 上层文件夹」 |
| 输入路径跳转 | ⌘L | 发「前往 › 前往文件夹…」 |
| 剪切 | ⌘X | 发「编辑 › 拷贝」，剪贴板里有文件才标记"待移动" |
| 粘贴（剪切后移动） | ⌘V | 只在剪切后接管，发「编辑 › 将项目移到这里」，只一次 |
| 新建文本文件 | ⌥⌘N | AppleScript 在当前位置新建并进入重命名 |
| 在终端中打开 | ⌥⌘T | 当前位置用所选终端打开 |

"发 Finder「…」"：从菜单快照按路径找当前快捷键（`MenuPath` 写了中英文路径），找不到用默认值；刚改、还没重启 Finder 的原生快捷键优先。
剪切作废：剪贴板之后又变了（在任何 App 里复制了别的），或者按了 Finder 的"拷贝"。

速查面板：Finder 在前台时只按住 ⌘（默认 0.8 秒），显示 MAIO 增强 + 菜单快照里所有带快捷键的项 + 不在菜单里的按键；松开 ⌘ 或按别的键消失。按键过滤器也收到 flagsChanged（只读）就是为了它。

## 原生快捷键

- 展示：`FinderMenuReader` 在后台遍历菜单栏（跳过苹果菜单、"服务"、"最近使用的文件夹"、窗口列表、标题随选中项变化的项）。
- 重设：写 Finder 的 `NSUserKeyEquivalents`（和系统设置里的 App 快捷键是同一份），键用完整菜单路径 `"\u{1B}文件\u{1B}新建文件夹"`（同名菜单项不会改错，2026-11-05 实测 Finder 认这种写法），值如 `"@$n"`；重启 Finder 生效。
- 🌐 快捷键（全屏、填充、居中等）由系统处理，只展示。

## 冲突提示（`Domain/FinderConflicts.swift`，ADR-0018）

红色"不会生效"：被系统快捷键占用；两个动作 / 两个菜单项用了同一个键；菜单项的键被 MAIO 动作或 MAIO 绑定截走。
橙色"会覆盖"：动作覆盖 Finder 菜单项；动作让 MAIO 全局绑定在 Finder 里不触发；不带修饰键的字母（会影响按名称跳转）。
灰色说明：粘贴只在剪切后接管、Finder 的剪切只对文字有效。
动作的快捷键会登记到快捷键目录，快捷键页里冲突的绑定显示"部分 App 中被占用"。

## 右键菜单（ADR-0019）

| 项 | 右键在 | 做什么 |
|---|---|---|
| 新建 ▸ 模板… | 空白处 | 复制模板（名字加"新建 "，重名加 2、3…），Finder 移进来并进入重命名 |
| 剪切 | 文件 | 同 ⌘X |
| 粘贴到这里 | 空白处 | 剪切过就移动，否则普通粘贴 |
| 复制路径 | 都有 | 选中项的路径（多个换行分隔），没选中就是当前文件夹 |
| 在终端中打开 | 都有 | 选中单个文件夹时打开它，否则当前文件夹 |
| 显示 / 隐藏隐藏文件 | 空白处 | 发 ⌘⇧. |

模板：`data/finder/templates/`，第一次使用时放入 文本、Markdown、RTF、Word、Excel；用户可以自己加。

## Finder 隐藏设置

列表在 `Domain/FinderTweaks.swift`，开 = 写入指定值，关 = 删除这个键（系统默认）。每次打开页面都直接读 Finder 的配置。
第一次改某项（包括原生快捷键）前，原值记在 `data/finder/backups.json`；"全部还原…"把隐藏设置和原生快捷键都写回原值。

## 命令

| 命令 | 参数 | 说明 |
|---|---|---|
| `finder.newTextFile` | 无 | 在当前位置新建文本文件 |
| `finder.openTerminal` | 无 | 在终端中打开当前位置 |
| `finder.restartFinder` | 无 | 重启 Finder |
| `finder.contextMenu` | `action`、`target`、`items` | 右键菜单扩展调用；`items` 每行一个路径，文件夹以 / 结尾 |

## 设置项

| 字段 | 默认值 | 说明 |
|---|---|---|
| `shortcuts` | `{}` | 动作 ID → `{isEnabled, chord}`；没有的用默认值 |
| `newFileName` | `新建文本文档.txt` | ⌥⌘N 新建的文件名 |
| `terminalBundleID` | `com.apple.Terminal` | 设置页列出已安装的常见终端（终端、Otty、iTerm2、Ghostty、Warp、kitty、WezTerm、Tabby、Hyper、Wave），也可以"选择其他 App…"；启动方式是用这个 App 打开文件夹 |
| `cheatSheetEnabled` / `cheatSheetDelay` | `true` / `0.8` | 速查面板 |
| `hiddenContextMenuItems` | `[]` | 右键菜单里关掉的项 |

## 权限

- 辅助功能（键盘 tap、读 Finder 焦点和菜单）。
- 自动化 › Finder：第一次新建文件 / 打开终端时系统弹窗。
- 右键菜单扩展要启用一次（设置页一键启用）。

## 已知限制

- 改不了 Finder 的外观、列表结构、地址栏；没有双栏和树形导航。
- 只对 Finder 生效，其他 App 的打开 / 保存面板不受影响。
- 标题会变的菜单项（"显示路径栏 / 隐藏路径栏"）改了快捷键后，标题一变就对不上。
- 右键菜单的"新建"在右键文件时不显示（Finder 给扩展的位置是文件所在的文件夹，容易误解，先不做）。
