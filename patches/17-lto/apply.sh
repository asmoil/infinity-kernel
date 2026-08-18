#!/usr/bin/env bash
# Patch 17: LTO (Link Time Optimization) Support
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_LTO_PATCHED"

# 1. Patch init/Kconfig for LTO options
KCONFIG="${KDIR}/init/Kconfig"
if [ -f "$KCONFIG" ] && ! grep -q "$MARKER" "$KCONFIG" 2>/dev/null; then
    # Add LTO config entries if not present
    if ! grep -q 'config LTO_CLANG' "$KCONFIG" 2>/dev/null; then
        cat >> "$KCONFIG" << 'LTO_KCFG'

# Infinity Kernel LTO Configuration
config LTO_CLANG
	bool "Clang Link Time Optimization (LTO)"
	depends on CC_IS_CLANG && ARCH_SUPPORTS_LTO_CLANG
	select LTO
	help
	  Enable Clang's Link Time Optimization. Produces smaller and
	  potentially faster binaries at the cost of longer build times.

config LTO_FULL
	bool "Full LTO (slower build, better optimization)"
	depends on LTO_CLANG
	help
	  Use -flto=full instead of -flto=thin. Full LTO produces
	  better optimization results but significantly increases
	  build time and memory usage.

	  If unsure, say N.
LTO_KCFG
        echo "[17-lto] Added LTO Kconfig entries"
    fi
    echo "/* $MARKER */" >> "$KCONFIG"
fi

# 2. Patch top-level Makefile for LTO flags
TOP_MAKE="${KDIR}/Makefile"
if [ -f "$TOP_MAKE" ] && ! grep -q "$MARKER" "$TOP_MAKE" 2>/dev/null; then
    # Add LTO flags before LDFLAGS_vmlinux
    if ! grep -q 'flto' "$TOP_MAKE" 2>/dev/null; then
        # Add thin LTO flags
        sed -i '/LDFLAGS_vmlinux/i\n# Infinity Kernel: LTO flags\nifdef CONFIG_LTO_FULL\n  LDFLAGS_vmlinux += -flto=full -ffat-lto-objects\nelse ifdef CONFIG_LTO_CLANG\n  LDFLAGS_vmlinux += -flto=thin\n  KBUILD_CFLAGS += -flto=thin\n  KBUILD_AFLAGS += -flto=thin\nendif\n' "$TOP_MAKE"
        echo "[17-lto] Added LTO flags to top Makefile"
    fi
    echo "# $MARKER" >> "$TOP_MAKE"
fi

# 3. Patch arch/arm64/Makefile for section garbage collection
ARM64_MAKE="${KDIR}/arch/arm64/Makefile"
if [ -f "$ARM64_MAKE" ] && ! grep -q "$MARKER" "$ARM64_MAKE" 2>/dev/null; then
    # Add function/data section flags for LTO
    if ! grep -q 'ffunction-sections.*LTO' "$ARM64_MAKE" 2>/dev/null; then
        # Add after existing CFLAGS
        sed -i '/KBUILD_CFLAGS.*+=/a\n# Infinity Kernel: section flags for LTO GC\nifeq ($(CONFIG_LTO_CLANG),y)\n  KBUILD_CFLAGS += -ffunction-sections -fdata-sections\n  LDFLAGS_vmlinux += --gc-sections\nendif\n' "$ARM64_MAKE"
        echo "[17-lto] Added section GC flags to arch/arm64/Makefile"
    fi
    echo "# $MARKER" >> "$ARM64_MAKE"
fi

echo "[17-lto] Done"