#!/usr/bin/env bash
set -euo pipefail

export ARCH=arm64
export SUBARCH=arm64
export CC=clang
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-

OUT_DIR=out

echo "[+] Using clang: $(command -v clang)"
echo "[+] Using CROSS_COMPILE: ${CROSS_COMPILE}"
echo "[+] Using CROSS_COMPILE_ARM32: ${CROSS_COMPILE_ARM32}"

echo "[+] Defconfig: lineageos_joan_defconfig"
make O=${OUT_DIR} lineageos_joan_defconfig

echo "[+] Building kernel..."
# Old 4.4 trees often fail with modern toolchains due to -Werror. Disable Werror.
make -j"$(nproc)" O=${OUT_DIR} WERROR=0 KCFLAGS="-Wno-error"

echo "[+] Done. Output: ${OUT_DIR}/arch/arm64/boot/Image.gz-dtb"
