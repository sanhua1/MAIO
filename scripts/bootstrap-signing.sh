#!/usr/bin/env bash
# 生成 Config/Signing.local.xcconfig：使用本机第一个 "Apple Development" 证书签名。
# 固定签名身份很重要：否则每次重新编译后，macOS 会要求重新授予辅助功能等权限。
set -euo pipefail
out="$(cd "$(dirname "$0")/.." && pwd)/Config/Signing.local.xcconfig"
[[ -f "$out" ]] && { echo "签名配置已存在：$out"; exit 0; }
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
if [[ -z "$identity" ]]; then
  echo "⚠️  未找到 Apple Development 证书，使用临时签名（每次编译后可能需要重新授权）"
  printf 'CODE_SIGN_IDENTITY = -\n' > "$out"
  exit 0
fi
team=$(security find-certificate -c "$identity" -p | openssl x509 -noout -subject | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')
printf "CODE_SIGN_IDENTITY = %s\nDEVELOPMENT_TEAM = %s\n" "${identity}" "${team}" > "$out"
echo "签名身份：${identity} (Team ${team})"
