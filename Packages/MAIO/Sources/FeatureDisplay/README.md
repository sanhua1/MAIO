# 外接显示器（`display`）

用 Mac 的音量键、亮度键调外接显示器的音量和亮度（DDC/CI），菜单栏菜单里放亮度滑块。spec：`docs/specs/M9-display.md`，ADR-0028。

- **音量键**（键盘、绑成音量键的鼠标侧键都行）：当前声音输出系统调不了（例如音箱接在显示器的耳机口、声音走 DP / HDMI），
  而且找到了对应的显示器时，由 MAIO 通过 DDC 调显示器自己的音量；其他输出照常交给系统。
- **亮度键**：鼠标在能用 DDC 调亮度的外接显示器上时调它；在内建屏上照常交给系统。
- 每按一下 1/16，⌥⇧ + 键微调 1/64，按住连续调；静音键切换静音（显示器不支持 DDC 静音时用"音量设 0、记住原值"）；
  ⌥ + 音量键 / 亮度键打开系统设置的「声音」/「显示器」。
- 菜单栏菜单最上面：每台外接显示器一组，名字下面是亮度条；声音正从这台显示器出来（音量键在调它）时下面再加一条音量条（拖动会取消静音）。都没有时不显示。
- 浮窗仿照系统：喇叭 / 太阳图标 + 16 格，微调时一格亮 1/4；显示的值对齐到 1/4 格（显示器只收整数，43.75% 会变成 44%）。

## 命令

无。

## 设置项

| 字段 | 默认值 | 说明 |
|---|---|---|
| `controlVolume` | `true` | 用音量键调外接显示器的音量 |
| `controlBrightness` | `true` | 用亮度键调外接显示器的亮度 |

设置页还有"状态"区：检测到的显示器、当前亮度 / 音量、当前声音输出由谁调节、「重新检测」按钮。

## 权限

辅助功能（媒体键走输入引擎的键盘 tap）。DDC 不需要额外权限（App 非沙盒）。

## 结构

| 位置 | 内容 |
|---|---|
| `Domain/DDCPacket.swift` | DDC 包编码、回复解析和校验 |
| `Domain/LevelStepper.swift` | 1/16、1/64 步进（对齐格点、整数容差），静音状态 |
| `Domain/Targeting.swift` | 音量键该调哪台、DDC 通道和屏幕的配对 |
| `Realtime/DisplayMediaKeyFilter.swift` | tap 线程上决定吞不吞媒体键 |
| `Infrastructure/DDCChannel.swift` | IOAVService 读写，串行队列，写入合并 |
| `Infrastructure/DisplayScanner.swift` | 遍历 IORegistry 找外接显示器的 DCPAVServiceProxy |
| `Infrastructure/AudioOutputMonitor.swift` | 当前声音输出、系统能不能调音量、切换输出的通知 |
| `Infrastructure/DisplayController.swift` | 扫描、按键处理、菜单滑块 |
| `UI/LevelHUD.swift` | 亮度 / 音量浮窗 |
| `UI/DisplayMenuView.swift` | 菜单栏亮度条、音量条 |

日志：`log show --last 10m --predicate 'subsystem == "app.maio" AND category == "display"' --info --debug`
（扫描结果、当前输出、音量键 / 亮度键交给谁、每次按键）。

## 参考

`references/MonitorControl`（MIT）：`MonitorControl/Support/Arm64DDC.swift`（IOAVService 读写、包格式、IORegistry 遍历与配对）、
`MonitorControl/Support/MediaKeyTapManager.swift`（哪些情况接管媒体键、⌥ 打开设置、⌥⇧ 微调）。

## 已知限制

- 只支持 Apple Silicon（IOAVService）。Intel Mac 的 DDC 走另一套 API，没做。
- 隔着某些扩展坞 / 转接头 DDC 不通；M1 / M2 的 Mac mini 自带 HDMI 口 DDC 不通（MonitorControl 的已知问题）。
- 系统的 OSDManager 浮窗在 macOS 27 上不显示，浮窗是自己画的，外观是仿的。
- 不播放调音量的"啵"提示音。
