# ADR-0019：Finder 右键菜单用 Finder Sync 扩展，动作交回主程序

- 状态：已采纳
- 日期：2026-11-05

## 背景

用户希望在 Finder 的右键菜单（右键文件、文件夹、空白处）里加"新建 ▸ 文本 / Word / Excel…"、剪切、粘贴、复制路径、在终端打开等。
不注入 Finder（ADR-0017）的前提下，唯一的官方途径是 Finder Sync 扩展（`FIFinderSync`）。

担心的问题：发布版用自签名证书（ADR-0016，没有 Team ID），系统是否接受这样签名的扩展。

## 实测（2026-11-05，macOS 26）

- 自签名证书由内向外签好的扩展：`pluginkit -a` 登记、`pluginkit -e use` 启用后，Finder 会启动扩展进程，右键菜单里出现扩展加的项（位置在"快速操作"下面）。
- `pluginkit -e use -i app.maio.MAIO.FinderSync` 可以在程序里直接启用，不用让用户去系统设置里找。
- 在 Finder 空白处右键：自定义项、"新建 ▸"子菜单都能显示；点击后 URL 交给主程序，剪贴板拿到了路径，没有多启动一个 MAIO。

## 决定

1. 新增 App 扩展目标 `MAIOFinderSync`（`FinderSync/`，`project.yml`），打包进 `MAIO.app/Contents/PlugIns/`。版本号放在工程级设置，和主程序共用。
2. **扩展必须开沙盒**，所以只负责显示菜单：
   - 菜单内容来自主程序写的 `data/finder/context-menu.json`（`ContextMenuConfig`）。扩展通过沙盒的只读例外
     `temporary-exception.files.home-relative-path.read-only` 读取 `~/Library/Application Support/MAIO/data/finder/`；
     沙盒里 home 指向容器，要用 `getpwuid` 取真实的用户目录。
   - 点击后打开 `maio://run/finder.contextMenu?action=…&target=…&items=…`，并且**指定交给扩展所在的那个 MAIO.app**
     （`NSWorkspace.open(_:withApplicationAt:)`，`activates = false`），装了多份 MAIO（Debug 版和安装版）时不会发错，Finder 也保持在前台。
   - Finder 回调时菜单项是复制过的，`representedObject` 带不回来，用 `tag` 找回动作 ID。
3. 主程序（不在沙盒里）执行动作，尽量复用键盘那套：剪切 = 发 Finder 的"拷贝"再标记待移动；粘贴 = 剪切过就发"将项目移到这里"，否则发"粘贴"；
   新建 = 模板先复制到临时目录（AppleScript 算好不重名的名字），再让 Finder `move` 进目标文件夹并进入重命名。文件由 Finder 写入，MAIO 不需要桌面、文稿等文件夹的授权。
4. 模板在 `data/finder/templates/`，第一次使用时放入 文本 / Markdown / RTF / Word / Excel（Word、Excel 是手写的最小 OOXML，用系统的 zip 打包）。用户可以自己往里放文件。
5. 发布：`make release` 先签扩展（用它自己的 entitlements），再签主程序，并检查扩展带着沙盒权限。

## 备选方案

- **服务菜单 / 快速操作**：不需要扩展，但藏在右键菜单底部的二级菜单里，空白处右键时没有。
- **App Group 共享配置**：macOS 15 起 App Group 要和 Team ID 匹配，自签名证书没有 Team ID，会弹"想访问其他 App 的数据"。
- **扩展里直接执行动作**：沙盒里不能写用户的文件夹、不能控制 Finder。

## 后果

- 用户要启用一次扩展（设置页一键启用，或系统设置 › 通用 › 登录项与扩展）。
- 本机同时有 Debug 版和 Release 版时，`pluginkit` 会登记两份同 ID 的扩展；开发时 `pluginkit -r <appex 路径>` 去掉多余的那份。
- `finder.contextMenu` 命令也能被任何 `maio://` 调用者触发；风险和已有的 `system.runShell` 等 URL 命令相同（只做剪切、粘贴、新建、复制路径）。
