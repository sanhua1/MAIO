# ADR-0005：系统快捷键冲突检测、带备份的禁用与一键恢复

- 状态：已采纳
- 日期：2026-11-02
- 关联：ADR-0004
- 修订：ADR-0004 的原结论（MAIO 拦不住系统 🌐 快捷键）已被更正——MAIO 运行时可以接管。冲突从"同时触发"改为"覆盖"，禁用系统快捷键从必选变为可选。

## 背景
用户把 Fn 组合绑定到 MAIO 命令时，如果与系统 🌐 快捷键相同，两者会同时触发（例如 fn+Q 同时打开快速备忘录）。
用户要求：检测到冲突时询问是否禁用系统快捷键，禁用前备份，并能一键恢复；同时让用户看到系统原有哪些 🌐 快捷键。

## 资料来源
- Apple「Mac 键盘快捷键」https://support.apple.com/zh-cn/102650 ——列出 Fn-A / Fn-C / Fn-N / Fn-Q / Fn-H / Fn-⇧A / Fn-D / Fn-E 等
- Apple「Mac 窗口平铺图标和键盘快捷键」https://support.apple.com/zh-cn/guide/mac-help/mchl9674d0b0/mac ——Fn-⌃F / C / R、Fn-⌃方向键等
- Apple **没有**公开"内部编号 → 功能"的对照表。编号来自实测（`scripts/diagnostics/list-globe-shortcuts.swift`）和系统设置资源（`KeyboardSettings.appex`）。

## 决定
1. **读取**：通过 dlsym 动态加载 SkyLight 私有函数 `CGSGetSymbolicHotKeyValue` / `CGSIsSymbolicHotKeyEnabled`，枚举编号 0–511，得到每个系统快捷键的实际组合键。
   启用状态以 `com.apple.symbolichotkeys` 偏好设置为准（同一进程内修改后，`CGSIsSymbolicHotKeyEnabled` 会返回旧值）。
2. **命名**：🌐 快捷键按**组合键**对照 Apple 文档命名（编号可能随系统版本变化，组合键更稳定）；经典快捷键按编号命名；其余显示"未公开说明 #编号"，如实告知。
3. **冲突判定**：组合键完全相同才算冲突。方向键、F 键、Home/End、媒体键（键码 > 126）的事件本身就带 Fn 位，比较时忽略 Fn。
4. **禁用**：同时修改两处——偏好设置（持久化，重启后仍有效）和 `CGSSetSymbolicHotKeyEnabled`（立即生效）。只把条目的 `enabled` 改为 false，保留其他字段；整数必须写回整数。
5. **备份**：首次禁用时把原始条目（不存在则记为"使用系统默认值"）和原启用状态写入 `config/system-shortcuts-backup.json`。重复禁用不覆盖最早的备份。
6. **恢复**：写回原始条目（原本不存在则删除条目），并恢复运行时状态；支持单个恢复、全部恢复，以及可绑定的命令 `maio.restoreSystemShortcuts`（也可以用 `maio://run/maio.restoreSystemShortcuts` 调用，设置窗口打不开时也能恢复）。
7. **交互**：绑定编辑器实时提示"覆盖系统快捷键"；保存时弹窗，提供"保存（MAIO 运行时接管）/ 保存并禁用系统快捷键 / 取消"三个选项；快捷键列表显示"与系统冲突"徽标；设置窗口新增"系统快捷键"页（冲突、已禁用可恢复、全部 🌐 快捷键说明）。
8. **降级**：私有函数不可用时（未来系统移除），整个功能显示为不可用，不影响其他功能。

## 验证
- 单元测试：`Tests/MAIOCoreTests/SystemShortcutTests.swift`（冲突判定、命名、备份/恢复往返、保留自定义条目、整数类型）
- 真实系统：`MAIO_SYSTEM_TESTS=1 swift test --package-path Packages/MAIO --filter SystemShortcutIntegration`（禁用后再恢复 🌐A，默认跳过）
- 2026-11-02 在 macOS 26.5 上实测：禁用 🌐Q 后 fn+Q 只打开 Otty；通过链接调用恢复 🌐A 后，配置条目被删除、状态回到启用。

## 后果
- 依赖私有 API 和系统偏好设置的格式，macOS 大版本升级后要用诊断脚本复查。
- 系统设置的"键盘快捷键"页面可能要重新打开才会显示 MAIO 改过的状态。
