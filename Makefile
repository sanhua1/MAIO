# MAIO 常用命令。交付前必须 `make check` 全绿。
# 注意：macOS 自带 make 3.81 不支持 .SHELLFLAGS，带管道的命令必须自己写 `set -o pipefail;`
SHELL := /bin/bash
PKG       := Packages/MAIO
BUILD_DIR := build
APP       := $(BUILD_DIR)/Build/Products/Debug/MAIO.app
# 发布签名证书（自签名，"MAIO Self-Signed Code Signing"）的 SHA-1。换证书会让所有用户的授权失效，见 ADR-0016
SIGN_ID   := DCD134758750C8627302A10DBC898AAB7488877F
XCODEBUILD := xcodebuild -project MAIO.xcodeproj -scheme MAIO -destination "platform=macOS,arch=arm64" -configuration Debug -derivedDataPath $(BUILD_DIR) -quiet

.PHONY: bootstrap build test lint format format-check arch check run install release new-feature references clean

bootstrap: ## 生成 Xcode 工程与本机签名配置
	@command -v xcodegen >/dev/null || { echo "请先 brew install xcodegen swiftlint swiftformat"; exit 1; }
	@scripts/bootstrap-signing.sh
	@xcodegen generate --quiet
	@echo "✅ 已生成 MAIO.xcodeproj"

build: MAIO.xcodeproj ## 构建 App
	@$(XCODEBUILD) build
	@echo "✅ 构建完成：$(APP)"

MAIO.xcodeproj: project.yml
	@$(MAKE) --no-print-directory bootstrap

test: ## 运行单元测试
	@set -o pipefail; swift test --package-path $(PKG) 2>&1 | { grep -v "^warning: 'maio'" || true; } | tail -n 5

lint: ## SwiftLint
	@swiftlint lint --quiet --strict

format: ## 自动格式化
	@swiftformat --quiet .

format-check:
	@swiftformat --lint --quiet .

arch: ## 架构边界校验
	@scripts/check-architecture.sh

check: format-check lint arch test build ## 交付前的完整检查
	@echo "✅ make check 全部通过"

run: build ## 构建并启动（会先退出正在运行的 MAIO）
	@pkill -x MAIO 2>/dev/null; sleep 0.5; open $(APP)

install: ## 构建并安装到 /Applications（登录启动建议使用安装版本）
	@xcodebuild -project MAIO.xcodeproj -scheme MAIO -configuration Release -derivedDataPath $(BUILD_DIR) -quiet build
	@pkill -x MAIO 2>/dev/null; sleep 0.5
	@rm -rf /Applications/MAIO.app && cp -R $(BUILD_DIR)/Build/Products/Release/MAIO.app /Applications/
	@open /Applications/MAIO.app && echo "✅ 已安装到 /Applications/MAIO.app"

VERSION := $(shell sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
RELEASE_DIR := $(BUILD_DIR)/release

release: MAIO.xcodeproj ## 打包发布版：自签名证书签名（ADR-0016），输出 build/release/MAIO-<版本>.zip
	@security find-identity -p codesigning | grep -q "$(SIGN_ID)" || { echo "❌ 钥匙串里没有发布签名证书 $(SIGN_ID)：从 signing/MAIO-signing.p12 导入，见 docs/adr/0016-self-update-and-signing.md"; exit 1; }
	@rm -rf $(RELEASE_DIR)
	@xcodebuild -project MAIO.xcodeproj -scheme MAIO -destination "platform=macOS,arch=arm64" -configuration Release \
		-derivedDataPath $(BUILD_DIR) -quiet build CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual
	@codesign --force --options runtime --timestamp=none --entitlements App/MAIO.entitlements \
		-s $(SIGN_ID) $(BUILD_DIR)/Build/Products/Release/MAIO.app
	@codesign --verify --strict $(BUILD_DIR)/Build/Products/Release/MAIO.app
	@codesign -d -r- $(BUILD_DIR)/Build/Products/Release/MAIO.app 2>&1 | grep -q "certificate leaf = H\"$$(echo $(SIGN_ID) | tr A-Z a-z)\"" || { echo "❌ 签名要求不对"; exit 1; }
	@mkdir -p $(RELEASE_DIR)
	@ditto -c -k --keepParent $(BUILD_DIR)/Build/Products/Release/MAIO.app $(RELEASE_DIR)/MAIO-$(VERSION).zip
	@shasum -a 256 $(RELEASE_DIR)/MAIO-$(VERSION).zip
	@echo "✅ 已打包：$(RELEASE_DIR)/MAIO-$(VERSION).zip"

new-feature: ## 新建功能：make new-feature NAME=ColorPicker ID=colorPicker
	@scripts/new-feature.sh "$(NAME)" "$(ID)"

references: ## 按清单拉取参考项目源码
	@scripts/fetch-references.sh

clean:
	@rm -rf $(BUILD_DIR) $(PKG)/.build
