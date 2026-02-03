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

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "[+] Using clang: $(command -v clang)"
echo "[+] Using CROSS_COMPILE: ${CROSS_COMPILE}"
echo "[+] Using CROSS_COMPILE_ARM32: ${CROSS_COMPILE_ARM32}"
echo "[+] Log file: ${LOG_FILE}"

echo "[+] Defconfig: lineageos_joan_defconfig"
make O=${OUT_DIR} lineageos_joan_defconfig

# Ensure KernelSU is enabled (the setup script adds CONFIG_KSU to defconfig, but double-check).
if ! grep -q "^CONFIG_KSU=y" "${OUT_DIR}/.config"; then
  echo "[!] CONFIG_KSU not set, enabling..."
  if [ -x scripts/config ]; then
    scripts/config --file "${OUT_DIR}/.config" -e KSU
  else
    echo "CONFIG_KSU=y" >> "${OUT_DIR}/.config"
  fi
  make O=${OUT_DIR} olddefconfig
fi

echo "[+] Building kernel..."
# Old 4.4 trees often fail with modern toolchains due to -Werror. Disable Werror.
make -j"$(nproc)" O=${OUT_DIR} WERROR=0 KCFLAGS="-Wno-error"

echo "[+] Done. Output: ${OUT_DIR}/arch/arm64/boot/Image.gz-dtb"
