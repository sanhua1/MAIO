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

### 鼠标滚动
- 鼠标滚轮单独反转方向（触控板保持自然滚动）。
- 平滑滚动，可调步长、速度、时长；按 App 设置例外。
- 按住 ⌘ 拨滚轮，模拟触控板双指捏合缩放（看图片、网页、地图时很有用）。

### 全局快捷键与系统动作
- 任意组合键（包括 Fn / 🌐 组合）绑定到任意命令：打开 App、打开网址或文件、运行 Shell / AppleScript / 快捷指令、发送按键（键位重映射），以及上面各个功能的命令。
- 每个快捷键可以设置生效范围（只在某些 App 里 / 除某些 App 外）。
- 检测和系统快捷键的冲突，可以一键禁用并在之后恢复系统快捷键。
- 所有命令也能通过 URL 调用：`open "maio://run/system.openApp?app=com.apple.Calculator"`。

## 系统要求

- macOS 26 或更高版本，Apple 芯片
- 从源码构建：Xcode 26、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、[SwiftLint](https://github.com/realm/SwiftLint)、[SwiftFormat](https://github.com/nicklockwood/SwiftFormat)

## 构建

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
```

## 权限

| 权限 | 用途 |
|---|---|
| 辅助功能 | 全局快捷键、滚动、窗口切换、读取选中文字和光标位置、粘贴 |
| 屏幕录制 | 截图、窗口缩略图 |

MAIO 不联网上传任何数据。只有翻译功能会把要翻译的文字发给你启用的翻译源。

## 用到的系统私有接口

为了做到公开接口做不到的效果，MAIO 用了几处私有接口。系统升级后它们可能失效，失效时只影响对应的那一项：

- 窗口切换：`_AXUIElementGetWindow`（窗口 ID）、SkyLight 的窗口聚焦接口（切到其他桌面 / 全屏窗口）。
- 滚轮缩放：触控板手势事件的私有字段。

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

GPL 项目只借鉴思路，没有复制代码；借鉴了具体做法的地方在代码注释里注明了出处。

## 许可证

[GPL-3.0](LICENSE)
