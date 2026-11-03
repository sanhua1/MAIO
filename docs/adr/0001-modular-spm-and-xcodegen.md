# ADR-0001：使用本地 SPM 多 target 划分模块，用 XcodeGen 生成工程

- 状态：已采纳
- 日期：2026-11-02

## 背景
项目会长期由 AI Agent 参与开发。模块边界如果只靠约定，很快就会被突破；`.pbxproj` 文件由 Agent 编辑，也容易损坏或产生合并冲突。

## 决定
- 所有代码放在 `Packages/MAIO` 本地 Swift Package 中，每个层次、每个功能各自是一个 target，依赖关系在 `Package.swift` 中显式声明，由编译器强制执行。
- App target 只是一个很薄的壳，由 XcodeGen 根据 `project.yml` 生成 `.xcodeproj`，生成物不提交到 git。

## 备选方案
- 单一 Xcode target + 文件夹分组：边界无法强制，否决。
- Tuist：能力更强，但对这个规模过重。
- 每个功能单独一个 Package：边界更硬，但管理成本高；同一个 Package 内的多 target 已经足够。

## 后果
- 跨模块访问必须是 `public`，会让 API 设计更显式。
- 新增功能需要修改 `Package.swift`，由 `make new-feature` 自动完成。
