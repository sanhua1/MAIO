#!/usr/bin/env bash
# 架构边界校验（见 docs/ARCHITECTURE.md §2、§11）。SPM 依赖已经在编译期强制大部分边界，
# 这里补充编译器管不到的规则。每条规则失败都会打印违规位置。
set -uo pipefail
cd "$(dirname "$0")/.."
SRC=Packages/MAIO/Sources
failed=0

fail() { echo "❌ $1"; echo "$2" | sed 's/^/     /'; failed=1; }
check() { # check "说明" "grep 结果"
  [[ -n "$2" ]] && fail "$1" "$2"
}

# 1. 模块 import 规则
check "功能模块只能 import MAIOKit / MAIOUI（禁止 MAIOCore、MAIOShell、其他功能）" \
  "$(grep -rnE '^\s*(@testable )?import (MAIOCore|MAIOShell|Feature)' $SRC/Feature* 2>/dev/null)"
check "MAIOKit 不能依赖任何 MAIO 模块或 AppKit" \
  "$(grep -rnE '^\s*import (MAIO|Feature|AppKit)' $SRC/MAIOKit)"
check "MAIOUI 不能依赖 MAIOCore / MAIOShell / 功能" \
  "$(grep -rnE '^\s*import (MAIOCore|MAIOShell|Feature)' $SRC/MAIOUI)"
check "MAIOCore 不能依赖 MAIOUI / MAIOShell / 功能" \
  "$(grep -rnE '^\s*import (MAIOUI|MAIOShell|Feature)' $SRC/MAIOCore)"

# 2. 禁止的 API
check "CGEventTap 只能在 MAIOCore/Input/ 中创建" \
  "$(grep -rn 'tapCreate' $SRC App | grep -v "^$SRC/MAIOCore/Input/")"
check "禁止直接使用 UserDefaults（用 context.settings）" \
  "$(grep -rn 'UserDefaults' $SRC App)"
check "功能之间禁止用 NotificationCenter 通信（用契约命令）" \
  "$(grep -rn 'NotificationCenter.default' $SRC/Feature* 2>/dev/null)"
check "禁止 try!" "$(grep -rn 'try!' $SRC App)"
check "event tap 回调禁止 \`self?.handle(...) ?? passUnretained\`（会把\"吞掉事件\"变成放行）" \
  "$(grep -rnE '\?\.[a-zA-Z]+\(.*\) \?\? Unmanaged\.passUnretained' $SRC)"

# 3. 目录约束
check "Domain/ 是纯逻辑，不能 import AppKit / SwiftUI" \
  "$(find $SRC -path '*/Domain/*.swift' -exec grep -HnE '^\s*import (AppKit|SwiftUI|Cocoa)' {} + 2>/dev/null)"
check "Realtime/ 在 tap 线程运行，不能使用主线程 API" \
  "$(find $SRC -path '*/Realtime/*.swift' -exec grep -HnE '@MainActor|MainActor\.|DispatchQueue\.main|NSApp\b|import (AppKit|SwiftUI)' {} + 2>/dev/null)"

# 4. 文件长度
long=$(find $SRC App Packages/MAIO/Tests -name '*.swift' -exec wc -l {} + | awk '$2 != "total" && $1 > 400 {print $2 " (" $1 " 行)"}')
check "单个文件不能超过 400 行" "$long"

# 5. 功能注册完整性
for dir in $SRC/Feature*/; do
  name=$(basename "$dir"); short=${name#Feature}
  [[ -f "$dir/README.md" ]] || fail "$name 缺少 README.md" "$dir"
  grep -q "\"$short\"," Packages/MAIO/Package.swift || fail "$name 未在 Package.swift 的 features 列表中" "$short"
  grep -q "import $name" App/FeatureCatalog.swift || fail "$name 未在 App/FeatureCatalog.swift 中注册" "$name"
  [[ -d "Packages/MAIO/Tests/${name}Tests" ]] || fail "$name 缺少测试目录" "Packages/MAIO/Tests/${name}Tests"
done

if [[ $failed -eq 0 ]]; then echo "✅ 架构校验通过"; else exit 1; fi
