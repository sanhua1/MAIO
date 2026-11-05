<p align="center">
  <img src="docs/images/icon.png" width="128" alt="MAIO 图标">
</p>

<h1 align="center">MAIO</h1>

<p align="center"><b>Mac All In One</b>：一个常驻菜单栏的 macOS 小工具合集</p>

MAIO 把日常离不开的几个小工具装进同一个 App：截图、翻译、剪贴板历史、Alt+Tab 窗口切换、鼠标滚动增强，再加上一套能绑定任意组合键（包括 Fn）的全局快捷键。

每个功能都是独立模块，可以单独开关，互不依赖。

> 这是个人项目，主要在作者自己的 Mac 上日常使用。用了一些系统私有接口（见下文），不会上架 App Store。

## 功能

### 截图
- 按下快捷键（默认 ⌥F1）先冻结整个屏幕，再在静止的画面上框选，打开的菜单、悬浮提示也能截进去。
- 自动识别鼠标下的窗口；按住 ⌘ 可以识别按钮、输入框等控件。框选时有放大镜，可以取色。
- 标注：矩形、椭圆、箭头、直线、画笔、荧光笔、文字、马赛克、模糊、序号，可以撤销，也能在历史里重新编辑。
- 贴图：把截图钉在屏幕上，可以缩放、调透明度。
- 截图历史。
- 识别文字（OCR，系统 Vision，本地运行）和截图翻译。
- 长截图：手动往下滚，自动拼接，右侧显示长条预览。

### 翻译
- 选中文字按 ⌥Q 翻译；没有选中文字时打开输入框。
- 多个翻译源同时请求：Google、必应、腾讯交互翻译等免费源，系统自带的 Apple 翻译（离线），以及 DeepL、百度、有道、腾讯、阿里、火山、彩云、小牛和大模型（OpenAI 兼容接口）等需要自己填 Key 的源。大模型逐字输出。
- API Key 存在系统钥匙串里。

### 剪贴板历史
- 记录文字、富文本、图片、文件路径，存在本地 SQLite。
- ⌃V 在文字光标处弹出列表（不在输入框里时弹在屏幕中央），回车粘贴，⇧回车粘贴纯文本，⌘1–9 快速粘贴。
- 可以固定条目、预览、搜索；按存储上限自动清理。
- 去重：同一段内容从不同 App 复制、终端"选中即复制"产生的多个版本，只保留最新一条。

### 窗口切换（Alt+Tab）
- 按住 ⌥ 连按 ⇥ 在所有窗口之间切换，松开 ⌥ 切过去；触发键可以改成 ⌘⇥ 等任意组合。
- 窗口缩略图、网格布局、方向键移动；切换时可以直接关闭、最小化、隐藏、退出。

### Finder 增强（默认关闭，在设置里打开）
- 像 Windows 资源管理器一样的按键：⏎ 打开、F2 重命名、⌦ 删除、⌫ 后退、⌥↑ 上一级、⌘L 输入路径、⌘X / ⌘V 剪切移动文件、⌥⌘N 新建文本文件、⌥⌘T 在终端中打开。每个都能开关、改键；重命名和搜索时不拦截。
- 按住 ⌘ 显示快捷键速查面板。
- 列出 Finder 自带的全部快捷键，可以直接改键。所有快捷键实时检查冲突（系统快捷键、MAIO 快捷键、Finder 菜单）。
- 右键菜单：新建（文本、Markdown、Word、Excel 等，可以放自己的模板）、剪切、粘贴到这里、复制路径、在终端中打开、显示 / 隐藏隐藏文件。
- 一键打开 Finder 的隐藏设置：显示隐藏文件和扩展名、路径栏、标题栏完整路径、文件夹排在前面、搜索当前文件夹、不在 U 盘和网络磁盘上生成 .DS_Store 等；改之前自动备份，可以一键还原。

### 启动器（默认关闭，在设置里打开）
- ⌘空格弹出搜索框（接管系统的聚焦搜索），搜应用支持拼音和首字母（`wx` 找到微信），常用的排前面。
- 全盘搜文件和文件夹，像 Windows 上的 Everything：自建索引，第一次约 10 秒，之后启动立即可用，新建 / 删除的文件实时更新。支持 Everything 语法：`|` 或、`!` 排除、`*.pdf` 通配符、`ext:`、`size:>100mb`、`dm:7d`、`in:~/Documents`、`regex:` 等。
- 搜 MAIO 自己的命令、系统操作（锁屏、睡眠、关机、清空废纸篓、切换深色模式）和系统设置的各个面板（蓝牙、显示器……）。
- Tab 或 ← → 切换来源（全部 / 应用 / 文件 / 文件夹 / 命令）；`g`、`bd` + 空格直接网页搜索。

### 鼠标滚动
- 鼠标滚轮单独反转方向（触控板保持自然滚动）。
- 平滑滚动，可调步长、速度、时长；按 App 设置例外。
- 按住 ⌘ 拨滚轮，模拟触控板双指捏合缩放（看图片、网页、地图时很有用）。

### 全局快捷键与系统动作
- 任意组合键（包括 Fn / 🌐 组合）绑定到任意命令：打开 App、打开网址或文件、运行 Shell / AppleScript / 快捷指令、发送按键（键位重映射），以及上面各个功能的命令。
- 每个快捷键可以设置生效范围（只在某些 App 里 / 除某些 App 外）。
- 检测和系统快捷键的冲突，可以一键禁用并在之后恢复系统快捷键。
- 所有命令也能通过 URL 调用：`open "maio://run/system.openApp?app=com.apple.Calculator"`。

## 安装

1. 到 [Releases](https://github.com/sanhua1/MAIO/releases) 下载最新的 `MAIO-<版本>.zip`，解压后把 `MAIO.app` 拖进「应用程序」文件夹。
2. **第一次打开要手动放行。** MAIO 用的是自签名证书，没有用付费的 Apple 开发者证书，也没有经过苹果公证，所以第一次双击时 macOS 会提示"无法验证开发者"或"已损坏"，不让打开。任选一种方法放行：
   - **系统设置**：先双击一次 MAIO（会被拦下），然后打开「系统设置 › 隐私与安全性」，在页面下方找到 MAIO 的提示，点「仍要打开」，输入密码确认。
   - **终端**：运行下面这行命令，去掉下载文件的隔离标记，之后就能直接双击打开：
     ```sh
     xattr -dr com.apple.quarantine /Applications/MAIO.app
     ```
3. **授予权限。** MAIO 常驻在菜单栏（没有程序坞图标），打开后在菜单栏点它的图标 →「设置…」→「权限」，按提示在「系统设置 › 隐私与安全性」里打开：
   - **辅助功能**：全局快捷键、滚动、窗口切换、剪贴板粘贴都需要；
   - **屏幕录制**（只有用截图、窗口缩略图时需要）。
   - 用 Finder 增强的右键菜单时，还要在「设置 › Finder 增强 › 右键菜单」里启用一次扩展；第一次新建文件或打开终端时，系统会询问是否允许 MAIO 控制 Finder，点「允许」。

   授权后如果快捷键还没生效，退出 MAIO 再打开一次。
4. 想开机自动启动：「系统设置 › 通用 › 登录项」里添加 MAIO。

### 升级

从 0.1.1 起 MAIO 会自动更新：每天检查一次 GitHub 上的新版本，在后台下载并校验签名，下载好后询问是否安装，点「安装并重启」即可。设置、数据和系统授权都会保留，不用再放行或重新授权。也可以在菜单栏点「检查更新…」，或者在「设置 › 通用 › 更新」里关掉自动检查。

自动更新要求 MAIO 放在「应用程序」文件夹里（直接从「下载」里打开的 App 是只读的，不能原地替换）。

**从 0.1.0 升级**（只需要一次）：0.1.0 没有自动更新，而且用的是临时签名，换成固定签名后系统会把它当成另一个 App。手动下载 0.1.1 替换旧版本、按上面第 2 步放行，然后到「系统设置 › 隐私与安全性 › 辅助功能」（以及「屏幕录制」）里把旧的 MAIO 删掉（选中后点「−」），再打开新 MAIO 的开关。也可以在终端里先清掉旧授权：

```sh
tccutil reset Accessibility app.maio.MAIO
tccutil reset ScreenCapture app.maio.MAIO
```

### 卸载

退出 MAIO，删除「应用程序」里的 MAIO.app。设置和数据（剪贴板历史、截图历史）在 `~/Library/Application Support/MAIO`，一并删除即可。翻译源的 API Key 存在钥匙串里，可以在「钥匙串访问」里搜索 `app.maio` 删除。

## 系统要求

- macOS 26 或更高版本，Apple 芯片（M 系列）
- 从源码构建：Xcode 26、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、[SwiftLint](https://github.com/realm/SwiftLint)、[SwiftFormat](https://github.com/nicklockwood/SwiftFormat)

## 从源码构建

```sh
brew install xcodegen swiftlint swiftformat
make bootstrap   # 生成 Xcode 工程和本机签名配置
make run         # 构建并启动
```

`make bootstrap` 会用钥匙串里第一个 "Apple Development" 证书签名。签名身份固定很重要：否则每次重新编译后，macOS 都会要求重新授予辅助功能等权限。没有证书时使用临时签名。

其他命令：

```sh
make test     # 单元测试
make check    # 格式 + lint + 架构校验 + 测试 + 构建
make release  # 打包发布版：build/release/MAIO-<版本>.zip
```

`make release` 用作者的自签名证书签名（自动更新靠它校验新版本、保留授权，见 [ADR-0016](docs/adr/0016-self-update-and-signing.md)）。自己 fork 发布的话，生成自己的代码签名证书，把 Makefile 里的 `SIGN_ID` 换成它的 SHA-1，并把 `Updater.defaultFeed` 指向自己的仓库。

## 权限

| 权限 | 用途 |
|---|---|
| 辅助功能 | 全局快捷键、滚动、窗口切换、读取选中文字和光标位置、粘贴 |
| 屏幕录制 | 截图、窗口缩略图 |
| 自动化（Finder） | Finder 增强：新建文件、打开终端、取当前文件夹；启动器：清空废纸篓 |
| 自动化（System Events） | 启动器：切换深色模式 |
| 完全磁盘访问（可选） | 启动器：文件搜索包含桌面、文稿、下载等受保护位置 |

MAIO 不联网上传任何数据。只有翻译功能会把要翻译的文字发给你启用的翻译源；检查更新时会访问 GitHub 的发布接口（不带任何个人信息，可以在设置里关掉）。

## 用到的系统私有接口

为了做到公开接口做不到的效果，MAIO 用了几处私有接口。系统升级后它们可能失效，失效时只影响对应的那一项：

- 窗口切换：`_AXUIElementGetWindow`（窗口 ID）、SkyLight 的窗口聚焦接口（切到其他桌面 / 全屏窗口）。
- 滚轮缩放：触控板手势事件的私有字段。
- 启动器的「锁定屏幕」：login.framework 的 `SACLockScreenImmediate`（和菜单栏「锁定屏幕」相同）。

## 项目结构

```
App/                    App 入口、功能清单、图标
Packages/MAIO/
  Sources/
    MAIOKit/            功能可见的协议和契约（唯一的公共依赖）
    MAIOUI/             共享界面组件
    MAIOCore/           输入引擎（CGEventTap）、设置、权限等实现
    MAIOShell/          设置窗口、菜单栏、命令路由
    Feature*/           各个功能，只依赖 MAIOKit 和 MAIOUI
  Tests/
docs/                   架构、决策记录（ADR）、功能规格
```

功能之间不直接依赖，跨功能协作通过 `MAIOKit/Contracts` 里的契约命令。架构说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，新增功能的流程见 [docs/FEATURE_GUIDE.md](docs/FEATURE_GUIDE.md)，重要决定见 [docs/adr/](docs/adr/)。

## 致谢

开发时参考了这些开源项目的思路（清单和许可证见 [references/README.md](references/README.md)）：

- [Mos](https://github.com/Caldis/Mos)：平滑滚动
- [alt-tab-macos](https://github.com/lwouis/alt-tab-macos)：窗口切换
- [Maccy](https://github.com/p0deje/Maccy)、[Ditto](https://github.com/sabrogden/Ditto)：剪贴板
- [pot-desktop](https://github.com/pot-app/pot-desktop)：翻译
- [flameshot](https://github.com/flameshot-org/flameshot)、[ShareX](https://github.com/ShareX/ShareX)、[Snow Shot](https://github.com/mg-chao/snow-apps)：截图与长截图
- [LinearMouse](https://github.com/linearmouse/linearmouse)：滚轮缩放
- [oil-find](https://github.com/oil-oil/oil-find)、[Cardinal](https://github.com/cardisoft/cardinal)：启动器的文件索引与搜索语法

GPL 项目只借鉴思路，没有复制代码；借鉴了具体做法的地方在代码注释里注明了出处。

## 许可证

[GPL-3.0](LICENSE)
