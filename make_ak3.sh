#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
AKDIR="$ROOT/AnyKernel3"
KSUDIR="$ROOT/KernelSU"
OUT_IMG="$ROOT/out/arch/arm64/boot/Image.gz-dtb"
OUT_DIR="$ROOT/out/arch/arm64/ak3"
DEVICE_NAME="joan"

if [ ! -f "$OUT_IMG" ]; then
  echo "[!] 未找到内核镜像: $OUT_IMG"
  exit 1
fi

if [ ! -d "$AKDIR" ]; then
  echo "[!] 未找到 AnyKernel3 目录: $AKDIR"
  exit 1
fi

mkdir -p "$OUT_DIR"

# 拷贝内核
cp -f "$OUT_IMG" "$AKDIR/Image.gz-dtb"

# 动态获取 ReSukiSU 版本信息（和 KernelSU/kernel/Kbuild 同逻辑）
KSU_API_VERSION="$(sed -n 's/^KSU_VERSION_API := //p' "$KSUDIR/kernel/Kbuild" | head -n1)"
KSU_BRANCH="$(sed -n 's/^REPO_BRANCH := //p' "$KSUDIR/kernel/Kbuild" | head -n1)"
[ -n "$KSU_API_VERSION" ] || KSU_API_VERSION="unknown"
[ -n "$KSU_BRANCH" ] || KSU_BRANCH="main"

if [ -d "$KSUDIR/.git" ]; then
  # Keep consistent with KernelSU/kernel/Kbuild:
  # KSU_LOCAL_VERSION := git rev-list --count $(REPO_BRANCH)
  if [ -f "$KSUDIR/../.git/shallow" ]; then
    git -C "$KSUDIR" fetch --unshallow >/dev/null 2>&1 || true
  fi
  KSU_SHORT_HASH="$(git -C "$KSUDIR" rev-parse --short=8 HEAD)"
  KSU_LOCAL_COUNT="$(git -C "$KSUDIR" rev-list --count "$KSU_BRANCH")"
  KSU_VERSION_CODE="$((30000 + KSU_LOCAL_COUNT + 700))"
  KSU_VERSION_NAME="v${KSU_API_VERSION}-${KSU_SHORT_HASH}@ReSukiSU"
else
  KSU_VERSION_CODE="unknown"
  KSU_VERSION_NAME="v${KSU_API_VERSION}-unknown@ReSukiSU"
fi

# 打包到 out/arch/arm64/ak3
TS=$(date +%Y%m%d-%H%M%S)
if [ -f "$ROOT/out/include/config/kernel.release" ]; then
  KERNEL_UNAME=$(cat "$ROOT/out/include/config/kernel.release")
else
  KERNEL_UNAME="unknown-kernel"
fi
KERNEL_UNAME="${KERNEL_UNAME%%+}"

if [ -n "${AK3_SUSFS_MODE:-}" ]; then
  case "${AK3_SUSFS_MODE}" in
    on) BUILD_FLAVOR="susfs" ;;
    off) BUILD_FLAVOR="manualhook" ;;
    *) BUILD_FLAVOR="${AK3_SUSFS_MODE}" ;;
  esac
elif grep -q '^CONFIG_KSU_SUSFS=y' "$ROOT/out/.config" 2>/dev/null; then
  BUILD_FLAVOR="susfs"
else
  BUILD_FLAVOR="manualhook"
fi

ZIP_PATH="$OUT_DIR/${DEVICE_NAME}-ReSukiSU@${KSU_VERSION_NAME}-${KSU_VERSION_CODE}-${BUILD_FLAVOR}-${KERNEL_UNAME}-${TS}.zip"

python3 - <<PY
import os, zipfile
base = "${AKDIR}"
out = "${ZIP_PATH}"
exclude = {'.git', '.github'}
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(base):
        rel_root = os.path.relpath(root, base)
        dirs[:] = [d for d in dirs if d not in exclude]
        for f in files:
            if rel_root == '.':
                arc = f
            else:
                arc = os.path.join(rel_root, f)
            z.write(os.path.join(root, f), arc)
print(out)
PY

echo "[+] AK3 已生成: $ZIP_PATH"
