#!/usr/bin/env bash
# 按 references/manifest.tsv 拉取参考项目到 references/<name>，并固定到指定 commit。
# 用法：scripts/fetch-references.sh [name ...]   （不带参数则拉取全部）
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/references"
while IFS=$'\t' read -r name url commit _license; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  if [[ $# -gt 0 ]] && [[ ! " $* " == *" $name "* ]]; then continue; fi
  dest="$dir/$name"
  if [[ ! -d "$dest/.git" ]]; then
    echo "==> clone $name"
    git clone --quiet --filter=blob:none "$url" "$dest"
  fi
  echo "==> $name @ $commit"
  git -C "$dest" fetch --quiet origin "$commit" 2>/dev/null || git -C "$dest" fetch --quiet --unshallow origin 2>/dev/null || true
  git -C "$dest" -c advice.detachedHead=false checkout --quiet "$commit"
done < "$dir/manifest.tsv"
