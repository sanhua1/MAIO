#!/usr/bin/env bash
# 新建功能模块：scripts/new-feature.sh ColorPicker colorPicker
# 生成目录与测试，并在 Package.swift、App/FeatureCatalog.swift 中注册。
set -euo pipefail
name="${1:-}"; id="${2:-}"
if [[ ! "$name" =~ ^[A-Z][A-Za-z0-9]+$ || ! "$id" =~ ^[a-z][A-Za-z0-9]+$ ]]; then
  echo "用法：make new-feature NAME=ColorPicker ID=colorPicker"
  echo "  NAME：大驼峰类型名；ID：小驼峰功能 ID（发布后不可更改）"
  exit 1
fi
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
src="Packages/MAIO/Sources/Feature$name"; tests="Packages/MAIO/Tests/Feature${name}Tests"
[[ -e "$src" ]] && { echo "已存在：$src"; exit 1; }
grep -q "id: \"$id\"" -r Packages/MAIO/Sources && { echo "功能 ID 已被使用：$id"; exit 1; }

copy() { # copy 模板目录 目标目录
  mkdir -p "$2"
  (cd "$1" && find . -type f) | while read -r f; do
    dest="$2/${f//__NAME__/$name}"
    mkdir -p "$(dirname "$dest")"
    sed -e "s/__NAME__/$name/g" -e "s/__ID__/$id/g" "$1/$f" > "$dest"
  done
}
copy Templates/Feature/Sources "$src"
copy Templates/Feature/Tests "$tests"

sed -i '' "s|    // @new-feature-marker|    \"$name\",\n    // @new-feature-marker|" Packages/MAIO/Package.swift
sed -i '' "s|// @new-feature-import|import Feature$name\n// @new-feature-import|" App/FeatureCatalog.swift
sed -i '' "s|        // @new-feature-catalog|        ${name}Feature.self,\n        // @new-feature-catalog|" App/FeatureCatalog.swift

echo "✅ 已创建 $src"
echo "下一步：填写 manifest 与 README.md，然后运行 make check（见 docs/FEATURE_GUIDE.md）"
