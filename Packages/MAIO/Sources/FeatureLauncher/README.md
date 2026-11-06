# 启动器（`launcher`）

系统聚焦搜索（⌘空格）的加强版，融合 Raycast：搜应用（支持拼音、首字母，常用的排前面）、全盘搜文件（像 Everything）、
MAIO 命令 / 系统操作 / 系统设置面板、网页搜索，Tab 切换来源。
需求与分阶段计划见 `docs/specs/M7-launcher.md`。**P1～P4 全部完成**（面板、应用、拼音、常用排序、网页搜索、文件索引、Everything 语法、命令）。
开发中，默认关闭。

## 工作方式

```
⌘空格 → launcher.show → LauncherController：记下当前 App → 强制激活 MAIO → 面板成为焦点（中文输入法可用）
输入 → LauncherQuery.parse（前缀 / 搜索引擎关键词）→ LauncherRanking（MatchScore + UsageBook）→ 分组结果
⏎ → 记一次常用度（data/launcher/usage.json）→ 关闭面板 → NSWorkspace 打开
```

应用目录（`AppCatalog`）：`/Applications`、`~/Applications`、`/System/Applications`、`/System/Library/CoreServices/Applications`（往下两层，不进 .app），加上 Finder。
启动时在后台扫描（约 0.5 秒，149 个应用）；打开面板时如果列表超过 60 秒没刷新，就后台重扫，扫完自动更新结果。
每个应用的可搜索名称：显示名、文件名、`CFBundleDisplayName` / `CFBundleName`（本地化和原始），**另外总是读取简体中文名**
（`zh-Hans.lproj/InfoPlist.strings`，系统应用是 `InfoPlist.loctable`），英文界面下也能用拼音搜到中文名。

## 文件索引（`Index/`，ADR-0020）

```
启动 → index.bin 设置指纹、事件库 UUID 都对得上？ → 读盘（0.3 秒）→ 从存盘时的事件编号回放
                                         否 → 记下事件编号、开始监视 → 全盘扫描（10 秒左右）→ 补上扫描期间的事件 → 存盘
FSEvents（逐文件，0.15 秒）→ IndexUpdater：lstat → 删子树 / 补父目录链再加 / 更新大小时间 → 有变化时每 30 分钟存盘
搜索 → FileSearchClient（编号，只要最新）→ FileIndex.search：memmem 并行扫名称块 + 拼音键 → 过滤 → 打分取前 N
```

| 文件 | 内容 |
|---|---|
| `DirectoryReader` / `FileScanner` | getattrlistbulk 读目录；多线程扫描，父目录编号小于子项 |
| `IndexData`（+Build、+Search、+Compact）/ `EntryLookup` | SoA 存储、批量追加、搜索打分、删除标记和压缩、路径查找 |
| `AltKeys` | 含汉字名称的拼音全拼、首字母键 |
| `IndexUpdater` / `FSEventsWatcher` | 增量更新、事件监视 |
| `IndexPersistence` | 存盘 / 读盘（读盘时校验长度、偏移、父目录编号） |
| `IndexConfiguration` | 默认排除目录、受保护位置、完全磁盘访问检测、设置指纹 |
| `FileIndex`（actor） | 启动流程、事件、存盘、搜索 |

查询：Everything 兼容语法（下一节），`Domain/QueryParser` 解析成语法树，`Index/QueryEvaluator` 执行：
先从"必须满足"的条件里取最长的一段文字用 memmem 粗筛（`ext:` 用 `.扩展名`，`regex:` 用 `RegexLiteral` 抽出的必有文字，`OR` 各分支取并集），
取不到（只有 `dm:`、`size:`、`!` 这类）就逐条检查全部；再对候选逐条检查整棵语法树。
逐条检查是单线程的：试过分段并行，多线程同时读同一批 Swift 数组时引用计数的原子操作互相争抢，慢了 10～20 倍。
排序（参考 oil-find）：匹配质量（同名 / 去掉扩展名同名 > 开头 > 词边界 > 包含；拼音算词边界）
+ 用户目录 +60、.app +150、文件夹 +20、最近修改 +10～60；依赖目录（含各 App 的 Caches、*.noindex）−350、包内部 −300、隐藏 −200、每层深度 −5。
默认排除：`/System`、`/Volumes`、`/Network`、`/dev`、`/private/var`、`/private/tmp`、各级 Caches / Logs、CloudStorage、Metadata、Biome、废纸篓。
没有完全磁盘访问时再排除桌面、文稿、下载、各 App 的容器等受保护位置（`IndexConfiguration.protectedPaths`）。

## 文件搜索语法（参考 Cardinal doc/pub/search-syntax.md）

| 写法 | 意思 |
|---|---|
| `报告 2024` | 名称同时包含两个词（空格 = 并且） |
| `报告\|总结`、`报告 OR 总结` | 或 |
| `!草稿`、`NOT 草稿` | 不要 |
| `( )` | 分组。优先级 `!` > `\|` > 空格：`a b\|c` = `a 并且 (b 或 c)` |
| `"Application Support"` | 短语（引号里的空格、`*`、`/` 都是普通文字） |
| `*.pdf`、`IMG_????.jpg` | 通配符，匹配整个名称（`?` 是一个字符，汉字也算一个） |
| `/rep`、`port/`、`/report/` | 名称以…开头 / 以…结尾 / 完全相同 |
| `foo/bar/ba` | 路径段：条目名以 ba 开头，父目录叫 bar，再上一级以 foo 结尾（返回条目本身，不含它下面的内容） |
| `src/**/*.swift`、`node_modules/**` | `**` 跨任意多层；结尾的 `**` 表示"在这个目录下面" |
| `file:`、`folder:`、`folder:图片` | 只要文件 / 只要文件夹（可以带名称） |
| `ext:pdf;docx` | 扩展名（.app 等包也算） |
| `type:picture`、`audio:`、`video:`、`doc:`、`exe:` | 类别（`FileTypes`） |
| `in:~/Documents`、`parent:/path`、`nosubfolders:/path` | 在某目录下（任意深度）/ 直接子项 / 目录本身和直接的文件；带空格的路径加引号 |
| `size:>100mb`、`size:1mb..10mb`、`size:!=0`、`size:huge` | 大小（1024 进制；关键词 empty tiny small medium large huge gigantic） |
| `dm:today`、`dm:7d`、`dm:>=2024-01-01`、`dm:2024-01..2024-03` | 修改时间（关键词 today yesterday this/last/past + week/month/year） |
| `regex:^readme\.md$` | 正则（不区分大小写，匹配名称） |

没做：`content:`（文件内容）、`tag:`（Finder 标签）、`dc:`（创建时间，索引里没存）、`< >` 分组、区分大小写。
写错的地方不报错：括号不配对当作配上，不认识的 `xxx:` 当普通文字，值写错的过滤条件（`size:abc`）什么都不匹配。

实测（本机 146 万条）：普通词 5～15 ms；`ext:`、`*.md`、`in:`、组合条件 4～30 ms；`dm:`、`size:` 约 20 ms；
`type:picture`（18 个扩展名）160 ms；`src/**/*.swift`（逐条检查路径）150 ms；`regex:` 有必有文字时 15 ms，没有时约 1 秒。

## 匹配（`Domain/MatchScore.swift`）

名称拆成词：英文按空格、符号、大小写变化、字母和数字的交界；每个汉字一个词，写法 = 字本身 + 各个拼音读音。
每个词可以写全、只写首字母，最后一个词可以只写开头：`wx`、`weixin`、`wxin`、`微x` 都能找到微信，`vsc` 找到 Visual Studio Code。

| 档次 | 分数 |
|---|---|
| 名称完全相同 | 100 |
| 名称开头 | 90 |
| 从第一个词开始按词匹配 | 75 |
| 从中间的词开始按词匹配 | 60 |
| 包含 | 50 |
| 按顺序出现（≥ 2 个字符） | 20 |

再加常用度（`UsageBook`：每次打开 +1，一周减半，最多 +30；同样的输入以前选过它 +25～40）和正在运行（+3）。
多音字：系统逐字转换只给一个读音（"音乐" → yin le），`Pinyin.polyphones` 补了常见多音字的其他读音。

## 面板里的按键

| 按键 | 作用 |
|---|---|
| ↑ / ↓、⌃P / ⌃N | 选择 |
| ⏎ | 打开 |
| ⌘⏎ | 在 Finder 中显示 |
| ⌘C / ⌘⇧C | 复制路径 / 复制文件（搜索框里选中了文字时 ⌘C 是普通复制） |
| ⌘1～⌘9 | 打开第几项 |
| ⇥ / ⇧⇥、→ / ← | 切换来源（在输入里移动光标用 ⌥← / ⌘← 等带修饰键的方向键） |
| ⌫（输入为空） | 回到"全部" |
| Esc | 有输入先清空，再按关闭 |

输入法正在组字时，所有按键都交给输入法。

前缀：`a ` 只搜应用，`f ` 只搜文件和文件夹，`d ` 只搜文件夹，`>` 只搜命令；搜索引擎关键词 + 空格（`g`、`bd`、`bi`、`gh`）直接网页搜索。

## 命令来源（P4，ADR-0021）

"全部"里排在应用后面，最多 3 项；"命令"标签（或 `>` 前缀）里全部列出，输入为空时按 最近使用 / MAIO 命令 / 系统操作 / 系统设置 分组。
⏎ 执行时先关面板、把焦点还给原来的 App，等 150 ms 再执行（"在 Finder 当前位置……""窗口截图"要看最前面的 App）；失败时 HUD 提示。

| 类别 | 来源 | 说明 |
|---|---|---|
| MAIO 命令 | `context.commands.availableCommands()`（每次打开面板时取） | 只列已启用功能实际注册的；不列启动器自己的命令，也不列有必填参数的命令（例如"打开 App""运行 Shell 命令"）。副标题是功能名，`截图 历史` 这样带功能名也能搜到 |
| 系统操作 | `Domain/SystemAction.swift` + `Infrastructure/SystemActionRunner.swift` | 锁定屏幕（login.framework 的 `SACLockScreenImmediate`，运行时查找）、睡眠 / 关闭显示器（`pmset`）、屏幕保护程序、退出登录 / 重新启动 / 关机（给 loginwindow 发"显示确认框"的 Apple 事件，系统弹确认框）、清空废纸篓（MAIO 先确认，再让 Finder 清空）、切换深色模式（System Events） |
| 系统设置面板 | `Infrastructure/SettingsPaneCatalog.swift` | 读 `/System/Library/ExtensionKit/Extensions` 里扩展点为 `com.apple.Settings.extension.ui` 且允许 URL 打开的扩展（本机 46 个，约 80 ms，和应用一起后台扫描）。名称用系统语言（`InfoPlist.loctable`，没有时用侧边栏名称键查 `Localizable.loctable`），英文名也能搜；"电池 / 节能"按有没有电池选。图标取扩展包本身的图标（和系统设置侧边栏一样）。打开：`x-apple.systempreferences:<bundle ID>` |

## 命令

| 命令 | 默认快捷键 | 说明 |
|---|---|---|
| `launcher.show` | ⌘空格 | 打开 / 关闭（来源 = 全部） |
| `launcher.showApps` | 不设 | 打开并进入"应用"来源 |

## 设置项

| 字段 | 默认 | 说明 |
|---|---|---|
| `keepQuerySeconds` | 5 | 关闭后多少秒内再打开保留输入（0 = 清空） |
| `maxAppsInAll` | 5 | "全部"里最多几个应用 |
| `maxFilesInAll` | 20 | "全部"里最多几个文件（"文件"来源最多 300） |
| `fileSearchEnabled` | `true` | 文件搜索 |
| `excludedPaths` | `[]` | 额外不索引的目录 |
| `indexPackageContents` | `false` | 索引 .app 等包的内部 |
| `showRecents` | `true` | 输入为空时显示最近使用 |
| `showWebFallback` | `true` | "全部"最后一项是网页搜索 |
| `defaultEngine` | `g` | 默认引擎的关键词 |
| `engines` | Google / 百度 / 必应 / GitHub | 名称、关键词、URL 模板（`{query}`） |

## 权限

完全磁盘访问（可选）：没有时跳过桌面、文稿、下载等受保护位置，设置页提示。
检测方法（`IndexConfiguration.hasFullDiskAccess`）：依次试读 `~/Library/Safari`、`Mail`、`Messages`、`Cookies`、TCC 目录，有一个能读就有权限、被拒绝（EPERM）就没有、不存在就看下一个。这些位置没权限时不弹窗；桌面 / 文稿 / 下载会弹，不能拿来试。0.2.1 只看 `~/Library/Application Support/com.apple.TCC`，macOS 27 上这个目录不存在，永远误报没有权限。

## 已知限制

- ⌘空格和用户已有的同键绑定冲突时，排在前面的绑定生效（快捷键页会显示冲突），需要用户删掉其中一条。
- 多音字只补了一张常用表，不在表里的多音字只有系统给的那个读音。
- 应用新装 / 删除后最多 60 秒（下次打开面板时）才反映到结果里。
- 文件：不索引外接磁盘；文件名拼音的多音字只用系统给的读音；MAIO 退出时不存盘（下次启动回放事件补上）。
- `Package.swift` 给本模块 Debug 也开了 `-O`（ADR-0020），断点调试时变量可能看不到。
- 命令：有参数的命令不列出（没有参数输入界面）；切换深色模式第一次会请求"控制 System Events"的自动化权限，清空废纸篓会请求"控制 Finder"。
- 系统设置面板：只列出能用 URL 打开的顶层面板，不含面板里的子页面（例如"键盘 › 键盘快捷键"）；"通用"本身不是扩展，不在列表里（它下面的"关于本机""软件更新""储存空间"等都在）。
