# ADR-0022：改键分两层：系统 HID 层的映射 + event tap 层的分层

- 状态：已采纳（P1 部分已实现并实测）
- 日期：2026-11-06

## 背景
用户要用 MAIO 替代 Karabiner-Elements 的常用部分：设备级修饰键、全局的 Caps 分层、简单的全局改键（docs/specs/M8-keys.md）。
Karabiner 的做法是 root 进程独占每个实体键盘，再从 DriverKit 虚拟键盘发出按键。DriverKit 驱动需要苹果审批的 entitlement 和 Developer ID；
MAIO 是自签名（ADR-0016），做不了驱动，也做不了 root 常驻进程。

## 决定
1. **一对一的改键放在系统 HID 层**，在所有 event tap 之前生效、密码框里也生效、退出 MAIO 后仍然有效：
   - 设备级修饰键用系统设置"修饰键"的同一套：写当前主机全局偏好 `com.apple.keyboard.modifiermapping.<vendor>-<product>-0`，
     同时给键盘服务设 `HIDKeyboardModifierMappingPairs` 让它立即生效。键盘重新接上时系统自己从偏好读出来（实测），MAIO 不监听插拔。
   - 写服务属性用 monitor 类型的 `IOHIDEventSystemClient`（`IOHIDEventSystemClientCreateWithType`，IOKit 导出但不在公开头文件，dlsym 取；
     系统设置的键盘面板也用它）。不需要 root。公开的 simple client 读写都不行，`hidutil` 设这个属性也不生效。
   - 写系统的偏好用 `CFPreferences`（这是系统的设置，不是 MAIO 的设置，不受"禁止直接用 UserDefaults"约束；FeatureFinder 写 Finder 偏好是同样的情况）。
2. **需要判断逻辑的（分层、单键换组合键、绑定命令）放在 event tap 层**，用现有的 `InputService.registerKeyFilter`（ADR-0003）。
3. **Caps 分层**：macOS 在 event tap 之前就处理大写锁定，tap 拿不到可靠的按下 / 松开。做法：HID 层全局 `UserKeyMapping` 把 Caps 设成"无操作"
   （`0x700000000`，和系统设置里的"无操作"同值，不发任何键），按下 / 松开用 IOHIDManager 读键盘原始输入（不受映射影响，需要输入监控），
   tap 线程上的过滤器读这个状态决定层。不借用任何键值（用户的 F13～F24 另有用途）。实测 WASD、⇧ 叠加、连发、绑定命令都正常。

## 备选方案
- 借用已安装的 Karabiner 虚拟键盘驱动：需要 root，并且等于要求装 Karabiner。否决。
- 只用 event tap 做全部改键：一对一的修饰键改不干净（修饰键状态由系统维护），密码框里失效，MAIO 退出就没了。否决。
- 修饰键只写 HID 属性不写偏好：系统设置看不到，拔插、重启后丢失。否决。

## 后果
- 用了一个非公开头文件里的函数；系统改了它的行为时，设置页会显示"读不到系统的键盘服务"或"没能立即生效"。
- Karabiner 运行时会接管键盘，HID 层的设置对实体键盘不起作用，设置页检测它的后台进程并提示。
- event tap 层的限制（安全输入时不工作、合成按键）见 spec 5.1。
