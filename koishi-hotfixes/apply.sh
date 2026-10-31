#!/usr/bin/env bash
# 从 npm 基线重放 bren9np Koishi 实例的本地 hotfix，产出可直接部署的 tarball。
#
#   ./apply.sh          # 全部重放
#   ./apply.sh 02 04    # 只重放指定编号
#
# 产物：dist/<pkg>-<ver>-<sha256前12位>.tgz（与生产实例 /root/.koishi/local-packages 同名规则）
# 依赖：npm（能访问 registry）、tar、patch、node
set -euo pipefail

# 兼容 `source apply.sh`（brush 里 bash 会落到 WSL bash，无 npm）：source 时 $0 不是脚本路径
cd "$(dirname "${BASH_SOURCE[0]:-$0}")"
OUT="${OUT:-dist}"
WORK=".work"
mkdir -p "$OUT" "$WORK"

# 编号|包名|基线版本|补丁文件
ENTRIES=(
  "01|koishi-plugin-bilibili-notify|5.0.0-alpha.5|patches/01-koishi-plugin-bilibili-notify-5.0.0-alpha.5-hotfix.2.patch"
  "02|@bilibili-notify/api|0.2.0-alpha.2|patches/02-bilibili-notify-api-0.2.0-alpha.2-hotfix.15.patch"
  "03|@bilibili-notify/push|2.0.0-alpha.1|patches/03-bilibili-notify-push-2.0.0-alpha.1-hotfix.1.patch"
  "04|@bilibili-notify/image|0.0.1-alpha.2|patches/04-bilibili-notify-image-0.0.1-alpha.2-hotfix.2.patch"
  "05|@bilibili-notify/live|0.1.0-alpha.9|patches/05-bilibili-notify-live-0.1.0-alpha.9-hotfix.0.patch"
)

want=("$@")
selected() {
  [ ${#want[@]} -eq 0 ] && return 0
  for w in "${want[@]}"; do [ "$w" = "$1" ] && return 0; done
  return 1
}

for entry in "${ENTRIES[@]}"; do
  IFS='|' read -r id pkg ver patch <<<"$entry"
  selected "$id" || continue
  echo "== [$id] $pkg@$ver"
  [ -f "$patch" ] || { echo "   缺少补丁文件: $patch" >&2; exit 1; }

  rm -rf "$WORK/pkg" && mkdir -p "$WORK/pkg"
  base=$(npm pack "$pkg@$ver" --silent --pack-destination "$WORK" | tail -1)
  [ -f "$WORK/$base" ] || { echo "   基线下载失败: $pkg@$ver" >&2; exit 1; }
  tar -xzf "$WORK/$base" -C "$WORK/pkg" --strip-components=1

  ( cd "$WORK/pkg" && patch -p1 --no-backup-if-mismatch --quiet < "../../$patch" ) \
    || { echo "   补丁应用失败" >&2; exit 1; }

  out=$(npm pack "$WORK/pkg" --silent --pack-destination "$OUT" | tail -1)
  [ -f "$OUT/$out" ] || { echo "   打包失败" >&2; exit 1; }

  h=$(node -e "console.log(require('crypto').createHash('sha256').update(require('fs').readFileSync(process.argv[1])).digest('hex').slice(0,12))" "$OUT/$out")
  final="${out%.tgz}-$h.tgz"
  mv "$OUT/$out" "$OUT/$final"
  echo "   -> $OUT/$final  ($(node -e "console.log((require('fs').statSync(process.argv[1]).size/1024).toFixed(1)+' KiB')" "$OUT/$final"))"
done

rm -rf "$WORK"
echo "完成。产物在 $OUT/"
