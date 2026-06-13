#!/bin/bash
##########################################################################################
# Infinity Kernel - Apply Patches Script
# Poco X3 Pro (vayu/bhima) - Snapdragon 732G
#
# Usage: ./apply_patches.sh <kernel_source_dir>
#
# This script applies all Infinity Kernel patches to the kernel source tree.
# Run this after cloning the Poco X3 Pro kernel source.
##########################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="${SCRIPT_DIR}/../patches"

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}[ERROR] Kernel source directory not specified${NC}"
    echo -e "Usage: $0 <kernel_source_dir>"
    echo -e "Example: $0 ~/android/kernel/xiaomi-vayu"
    exit 1
fi

KERNEL_DIR="$(cd "$1" && pwd)"

# Verify kernel source exists
if [ ! -d "$KERNEL_DIR" ]; then
    echo -e "${RED}[ERROR] Kernel source directory not found: $KERNEL_DIR${NC}"
    exit 1
fi

if [ ! -f "$KERNEL_DIR/Makefile" ]; then
    echo -e "${RED}[ERROR] Not a valid kernel source (no Makefile): $KERNEL_DIR${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Infinity Kernel Patch Application     ${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Kernel source: ${GREEN}$KERNEL_DIR${NC}"
echo -e "Patches dir:   ${GREEN}$PATCHES_DIR${NC}"
echo ""

# Check if patches directory exists
if [ ! -d "$PATCHES_DIR" ]; then
    echo -e "${RED}[ERROR] Patches directory not found: $PATCHES_DIR${NC}"
    exit 1
fi

# Count patches
PATCH_COUNT=$(find "$PATCHES_DIR" -name "*.patch" -type f | wc -l)
if [ "$PATCH_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}[WARN] No patch files found in $PATCHES_DIR${NC}"
    exit 0
fi

echo -e "${BLUE}[INFO] Found $PATCH_COUNT patches to apply${NC}"
echo ""

# Apply each patch
APPLIED=0
FAILED=0
SKIPPED=0

for patch_file in $(find "$PATCHES_DIR" -name "*.patch" -type f | sort); do
    patch_name=$(basename "$patch_file")
    patch_desc=$(head -5 "$patch_file" | grep -oP 'Subject: \K.*' | head -1)

    echo -e "${YELLOW}[PATCH] $patch_name${NC}"
    echo -e "         ${patch_desc:-No description}"

    # Try to apply with 3-way merge (git am style)
    if cd "$KERNEL_DIR" && git apply --3way --check "$patch_file" 2>/dev/null; then
        cd "$KERNEL_DIR" && git apply --3way "$patch_file" 2>/dev/null
        echo -e "         ${GREEN}[OK] Applied successfully${NC}"
        ((APPLIED++))
    elif cd "$KERNEL_DIR" && patch --dry-run -p1 < "$patch_file" 2>/dev/null; then
        # Fallback: try plain patch
        cd "$KERNEL_DIR" && patch -p1 < "$patch_file"
        echo -e "         ${GREEN}[OK] Applied with patch command${NC}"
        ((APPLIED++))
    else
        # Try with more fuzz
        if cd "$KERNEL_DIR" && git apply --3way --3way --fuzz=3 "$patch_file" 2>/dev/null; then
            echo -e "         ${YELLOW}[OK] Applied with fuzz=3 (may need manual review)${NC}"
            ((APPLIED++))
        else
            echo -e "         ${RED}[FAIL] Could not apply automatically${NC}"
            echo -e "         ${RED}       Run manually: patch -p1 < $patch_file${NC}"
            ((FAILED++))
        fi
    fi

    echo ""
done

# Copy custom driver files
echo -e "${BLUE}[INFO] Installing Infinity Kernel custom drivers${NC}"

# Charging control driver
CHARGING_SRC="${SCRIPT_DIR}/../drivers/charging"
CHARGING_DST="${KERNEL_DIR}/drivers/charging"

if [ -d "$CHARGING_SRC" ]; then
    mkdir -p "$CHARGING_DST"
    cp -v "${SCRIPT_DIR}/../drivers/charging/"*.c "$CHARGING_DST/" 2>/dev/null || true
    cp -v "${SCRIPT_DIR}/../drivers/charging/Makefile" "$CHARGING_DST/" 2>/dev/null || true

    # Add to drivers Kconfig if not already present
    if ! grep -q "infinity_charging" "${KERNEL_DIR}/drivers/Kconfig" 2>/dev/null; then
        echo -e 'source "drivers/charging/Kconfig"' >> "${KERNEL_DIR}/drivers/Kconfig" 2>/dev/null
        echo -e "         ${GREEN}[OK] Charging driver added to drivers/Kconfig${NC}"
    fi

    if ! grep -q "charging" "${KERNEL_DIR}/drivers/Makefile" 2>/dev/null; then
        echo -e 'obj-$(CONFIG_INFINITY_CHARGING_CONTROL)\t+= charging/' >> "${KERNEL_DIR}/drivers/Makefile" 2>/dev/null
        echo -e "         ${GREEN}[OK] Charging driver added to drivers/Makefile${NC}"
    fi
fi

# Copy header files
HDR_SRC="${SCRIPT_DIR}/../include/linux/infinity_charging_control.h"
HDR_DST="${KERNEL_DIR}/include/linux/"

if [ -f "$HDR_SRC" ]; then
    cp -v "$HDR_SRC" "$HDR_DST" 2>/dev/null
    echo -e "         ${GREEN}[OK] Header files installed${NC}"
fi

# Copy defconfig
DEFCONFIG_SRC="${SCRIPT_DIR}/../arch/arm64/configs/infinity_defconfig"
DEFCONFIG_DST="${KERNEL_DIR}/arch/arm64/configs/"

if [ -f "$DEFCONFIG_SRC" ]; then
    cp -v "$DEFCONFIG_SRC" "$DEFCONFIG_DST"
    echo -e "         ${GREEN}[OK] Defconfig installed${NC}"
fi

# Print summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Patch Summary                      ${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "  Applied:  ${GREEN}$APPLIED${NC} / $PATCH_COUNT"
echo -e "  Failed:   ${RED}$FAILED${NC} / $PATCH_COUNT"
echo -e "  Skipped:  ${YELLOW}$SKIPPED${NC}"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo -e "${YELLOW}[WARN] Some patches failed to apply automatically.${NC}"
    echo -e "${YELLOW}       Review .rej files and resolve conflicts manually.${NC}"
    exit 1
else
    echo -e "${GREEN}[SUCCESS] All patches applied successfully!${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo -e "  1. cd $KERNEL_DIR"
    echo -e "  2. make ARCH=arm64 CROSS_COMPILE=aarch64-linux-android- infinity_defconfig"
    echo -e "  3. make ARCH=arm64 CROSS_COMPILE=aarch64-linux-android- -j\$(nproc)"
    echo ""
    echo -e "  Or use the build script:"
    echo -e "  ${GREEN}./build.sh $KERNEL_DIR${NC}"
fi