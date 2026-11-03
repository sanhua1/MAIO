# ADR-0006：指针事件补充像素位移、连续标志、目标 App；指针 tap 移到注释会话层

- 状态：已采纳
- 日期：2026-11-02
- 关联：ADR-0003（输入引擎），M1 FeatureScroll

## 背景
实现滚轮反转与平滑滚动（替换 Mos）时，M0 的 `PointerEvent` 信息不够：
1. 平滑滚动的步长、速度以**像素**计（Mos 默认步长 33.6px），只有"行"单位不够。
2. 需要区分三类来源：触控板/妙控鼠标（有手势阶段，不能碰）、已经平滑过的连续事件（Logitech 平滑滚动驱动、远程桌面，只能反转不能再平滑）、普通滚轮（反转 + 平滑）。M0 仅凭 `isContinuous` 判断设备类型，会把第二类误判成触控板。
3. App 例外规则应作用于**鼠标所指的 App**（滚动的实际目标），而不是前台 App。目标进程只有到会话层之后才有值，HID 层拿不到。

## 决定
- `PointerEvent` 新增只读字段：`pixelY` / `pixelX`（像素位移）、`isContinuous`；`device` 改为按手势阶段判断：有 scroll phase 或 momentum phase 时为 `.trackpad`（原 `.continuous` 更名），否则为 `.wheel`。
- `RealtimeEnvironment` 新增 `targetBundleID`（滚动事件目标进程的 bundle ID，引擎内部带缓存地解析）。
- 指针 tap 从 HID 层移到 `cgAnnotatedSessionEventTap` + `tailAppendEventTap`（与 Mos 相同）。MAIO 合成的滚动事件发到会话层，会再经过指针 tap，依靠合成标记识别并放行。键盘 tap 保持在 HID 层不变。
- `ScrollEventCodec` 写回时，整数行字段按比例换算（原实现把 0.1 行四舍五入成 1 行，会放大小幅滚动）。

## 后果
- 纯新增字段，现有代码只有 `.continuous` 改名这一处受影响。
- 注释会话层位于其他 App 的会话层 tap 之后，与 Mos 行为一致。
