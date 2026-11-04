# ADR-0016：发布版用自签名证书签名，自己实现自动更新

- 状态：已采纳
- 日期：2026-11-04

## 背景

用户希望 0.1.1 起能自动更新：自动检查、下载、安装、重启。

0.1.0 用临时签名（ad-hoc）发布。macOS 记录辅助功能、屏幕录制授权时，记的是 App 的签名要求（designated requirement）。临时签名的签名要求是本次编译的 cdhash（`cdhash H"…"`），每次编译都不同，系统会把新版本当成另一个 App：更新后快捷键、滚动、截图全部失效，要用户去系统设置删掉旧条目再重新授权。自动更新会让用户"一觉醒来快捷键没了"。

本机只有 Apple Development 证书，没有 Developer ID（每年 99 美元），不能公证。

## 决定

1. **发布版用自签名代码签名证书签名**："MAIO Self-Signed Code Signing"，RSA 3072，有效期 20 年（到 2046-10-30），SHA-1 `DCD134758750C8627302A10DBC898AAB7488877F`。签名要求变成 `identifier "app.maio.MAIO" and certificate leaf = H"dcd1…"`，所有版本都相同，授权跨版本保留。
   - 证书和私钥备份在仓库的 `signing/MAIO-signing.p12`（**.gitignore 忽略，绝不提交**：开源同步用 git archive 导出，提交了就会被公开）；备份密码在登录钥匙串的 "MAIO signing backup"。
   - `make release` 先临时签名构建，再用这张证书重签（hardened runtime），并检查签名要求。
   - 换电脑：`security import signing/MAIO-signing.p12 -k ~/Library/Keychains/login.keychain-db -P "$(security find-generic-password -a MAIO -s 'MAIO signing backup' -w)" -T /usr/bin/codesign`（密码要从旧电脑带过来）。
   - **丢了证书、换了证书，所有用户的授权都会失效一次。**
2. **自己实现更新器**（`MAIOShell/Update/`），不引入 Sparkle：
   - 每 24 小时（启动 30 秒后开始）请求 `api.github.com/repos/sanhua1/MAIO/releases/latest`；安装包必须叫 `MAIO-<版本>.zip`。
   - 发现新版本自动下载到 `~/Library/Caches/app.maio.MAIO/Updates/<版本>/`，校验 GitHub 给的 SHA-256（附件的 `digest`），用 ditto 解压，检查 bundle ID、版本号，**并且要求新 App 满足当前运行的 MAIO 的签名要求**，不满足就不安装。这一条既防篡改，也保证装上去之后授权一定还有效。
   - 下载好后弹窗询问（用户选择：自动下载、确认后安装）：安装并重启 / 稍后 / 跳过这个版本。
   - 安装：启动一个 `/bin/sh` 脚本，然后退出 MAIO；脚本等 MAIO 退出后把旧版本挪开、新版本挪进去、打开新版本；失败时恢复旧版本并打开。结果写在 `data/update-result.txt`，新版本启动时提示。
   - Debug 版（开发证书签名，装不了发布版）不自动检查；调试时用环境变量 `MAIO_UPDATE_FEED=file:///…json` 指向本地的发布信息。

## 备选方案

- **Sparkle**：成熟，但要引入第三方依赖、EdDSA 密钥、appcast 托管；它的签名校验和我们这里"同一签名要求"的校验是两回事，授权问题照样要靠固定签名解决。
- **Apple Development 证书签发布版**：签名里带着开发者邮箱；证书每年到期；苹果规定不能用于对外分发。
- **Developer ID + 公证**：最好，首次打开也不用手动放行，但每年 99 美元。以后买了的话，换证书会让授权失效一次，需要在发布说明里提醒。
- **全自动安装、不询问**：用户选择了询问。

## 后果

- 从 0.1.0（临时签名）升到 0.1.1 时授权会失效一次，0.1.0 也没有更新器，要手动安装；之后的版本自动更新、授权保留。
- 首次安装仍然要手动放行（没有公证）。自动更新下载的文件没有隔离标记（实测），不会再被拦。
- 签名证书成了需要妥善保管的东西；发布前 `make release` 会检查钥匙串里有没有这张证书。
- 自签名证书在钥匙串里显示"不受信任"（`CSSMERR_TP_NOT_TRUSTED`），不影响签名，`security find-identity -v` 看不到它，要去掉 `-v`。
- 没验证：放在「应用程序」文件夹里、由 MAIO 启动的替换脚本会不会触发 macOS 的"App 管理"权限提示（替换的是 MAIO 自己）。失败时脚本会恢复旧版本，新启动的 MAIO 会提示"更新没有完成"。
