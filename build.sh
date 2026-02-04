#!/usr/bin/env bash
set -euo pipefail

export ARCH=arm64
export SUBARCH=arm64
export CC=clang
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-

OUT_DIR=out
LOG_DIR=logs
LOG_FILE="${LOG_DIR}/build-$(date +%Y%m%d-%H%M%S).log"
DEFCONFIG="${DEFCONFIG:-lineageos_joan_defconfig}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
KSU_REF="${KSU_REF:-}"
SUSFS_MODE="${SUSFS_MODE:-on}"
AUTO_AK3=1
# 只在这里改内核后缀，确保产物 uname 可控。
KERNEL_LOCALVERSION="${KERNEL_LOCALVERSION:--Iseri_Nina}"

usage() {
  cat <<'EOF'
用法:
  ./build.sh [--susfs on|off] [--ksu-ref <ref>] [--localversion <suffix>] [--jobs <n>] [--defconfig <name>] [--no-ak3]

示例:
  ./build.sh --susfs on --ksu-ref main --localversion -Iseri_Nina
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --susfs)
      SUSFS_MODE="$2"
      shift 2
      ;;
    --ksu-ref)
      KSU_REF="$2"
      shift 2
      ;;
    --localversion)
      KERNEL_LOCALVERSION="$2"
      shift 2
      ;;
    --jobs)
      BUILD_JOBS="$2"
      shift 2
      ;;
    --defconfig)
      DEFCONFIG="$2"
      shift 2
      ;;
    --no-ak3)
      AUTO_AK3=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[!] 未知参数: $1"
      usage
      exit 1
      ;;
  esac
done

if [ "${SUSFS_MODE}" != "on" ] && [ "${SUSFS_MODE}" != "off" ]; then
  echo "[!] --susfs 仅支持 on/off，当前: ${SUSFS_MODE}"
  exit 1
fi

MAKE_ARGS=(O="${OUT_DIR}" LOCALVERSION="${KERNEL_LOCALVERSION}")

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [ -n "${KSU_REF}" ] && [ -d "KernelSU/.git" ]; then
  echo "[+] Switching KernelSU to ref: ${KSU_REF}"
  git -C KernelSU fetch --all --tags --prune || true
  git -C KernelSU checkout "${KSU_REF}"
fi

echo "[+] Using clang: $(command -v clang)"
echo "[+] Using CROSS_COMPILE: ${CROSS_COMPILE}"
echo "[+] Using CROSS_COMPILE_ARM32: ${CROSS_COMPILE_ARM32}"
echo "[+] Using LOCALVERSION: ${KERNEL_LOCALVERSION}"
echo "[+] SUSFS mode: ${SUSFS_MODE}"
if [ -d "KernelSU/.git" ]; then
  echo "[+] KernelSU HEAD: $(git -C KernelSU rev-parse --short=8 HEAD)"
fi
echo "[+] Log file: ${LOG_FILE}"

echo "[+] Defconfig: ${DEFCONFIG}"
make "${MAKE_ARGS[@]}" "${DEFCONFIG}"

# Ensure KernelSU is enabled (the setup script adds CONFIG_KSU to defconfig, but double-check).
if ! grep -q "^CONFIG_KSU=y" "${OUT_DIR}/.config"; then
  echo "[!] CONFIG_KSU not set, enabling..."
  if [ -x scripts/config ]; then
    scripts/config --file "${OUT_DIR}/.config" -e KSU
  else
    echo "CONFIG_KSU=y" >> "${OUT_DIR}/.config"
  fi
  make "${MAKE_ARGS[@]}" olddefconfig
fi

if [ ! -x scripts/config ]; then
  echo "[!] 缺少 scripts/config，无法自动切换 SUSFS/Manual Hook"
  exit 1
fi

if [ "${SUSFS_MODE}" = "on" ]; then
  scripts/config --file "${OUT_DIR}/.config" \
    -e KSU_SUSFS \
    -e KSU_SUSFS_SUS_PATH \
    -e KSU_SUSFS_SUS_MOUNT \
    -e KSU_SUSFS_SUS_KSTAT \
    -e KSU_SUSFS_SPOOF_UNAME \
    -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
    -e KSU_SUSFS_OPEN_REDIRECT \
    -e KSU_SUSFS_SUS_MAP \
    -d KSU_MANUAL_HOOK \
    -d KSU_MANUAL_HOOK_AUTO_SETUID_HOOK \
    -d KSU_MANUAL_HOOK_AUTO_INITRC_HOOK \
    -d KSU_MANUAL_HOOK_AUTO_INPUT_HOOK
else
  scripts/config --file "${OUT_DIR}/.config" \
    -d KSU_SUSFS \
    -d KSU_SUSFS_SUS_PATH \
    -d KSU_SUSFS_SUS_MOUNT \
    -d KSU_SUSFS_SUS_KSTAT \
    -d KSU_SUSFS_SPOOF_UNAME \
    -d KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
    -d KSU_SUSFS_OPEN_REDIRECT \
    -d KSU_SUSFS_SUS_MAP \
    -e KSU_MANUAL_HOOK \
    -e KSU_MANUAL_HOOK_AUTO_SETUID_HOOK \
    -e KSU_MANUAL_HOOK_AUTO_INITRC_HOOK \
    -e KSU_MANUAL_HOOK_AUTO_INPUT_HOOK
fi
make "${MAKE_ARGS[@]}" olddefconfig

echo "[+] Building kernel..."
# Old 4.4 trees often fail with modern toolchains due to -Werror. Disable Werror.
make -j"${BUILD_JOBS}" "${MAKE_ARGS[@]}" WERROR=0 KCFLAGS="-Wno-error"

echo "[+] Done. Output: ${OUT_DIR}/arch/arm64/boot/Image.gz-dtb"

# Auto-generate AnyKernel3 zip if build succeeded.
AK3_SCRIPT="./make_ak3.sh"
if [ "${AUTO_AK3}" = "1" ] && [ -x "${AK3_SCRIPT}" ]; then
  echo "[+] Generating AnyKernel3 package..."
  AK3_SUSFS_MODE="${SUSFS_MODE}" "${AK3_SCRIPT}"
else
  echo "[!] skip AK3 packaging."
fi
