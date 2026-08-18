#!/usr/bin/env bash
# Patch 09: zRAM Optimizations
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

ZRAM="${KDIR}/mm/zram/zram.c"
[ -f "$ZRAM" ] || { echo "[09-zram] zram.c not found, skipping"; exit 0; }

MARKER="INFINITY_ZRAM_PATCHED"
grep -q "$MARKER" "$ZRAM" 2>/dev/null && {
    echo "[09-zram] Already patched, skipping"
    exit 0
}

echo "[09-zram] Applying zRAM optimizations..."

# 1. Add copy_page optimization for zsmalloc compaction
if ! grep -q "zram_copy_page_opt" "$ZRAM" 2>/dev/null; then
    sed -i '/zram_page_is_same/a \
	/* Infinity Kernel: copy_page optimization for identical pages */\
	if (zram->comp_alg == ZRAM_LZ4_COMPRESS) {\
		struct page *dpage = alloc_page(GFP_KERNEL);\
		if (dpage) {\
			copy_page(page_address(dpage), page);\
			__free_page(dpage);\
		}\
	}' "$ZRAM"
    echo "[09-zram] Added copy_page optimization"
fi

# 2. Change default disksize to 5GB
if grep -q 'disksize = .*50.*\\* 1024 \* 1024' "$ZRAM" 2>/dev/null; then
    : # Already has large disksize
else
    sed -i 's/disksize = \([0-9]*\) \* 1024 \* 1024/disksize = 5 * 1024 * 1024 * 1024/g' "$ZRAM"
    echo "[09-zram] Set default disksize to 5GB"
fi

# 3. Force LZ4 compressor default
if ! grep -q 'ZRAM_LZ4_COMPRESS' "$ZRAM" 2>/dev/null; then
    sed -i '/zram->compressor/i \
	/* Infinity Kernel: default to LZ4 */\
	strlcpy(zram->compressor, "lz4", sizeof(zram->compressor));' "$ZRAM"
    echo "[09-zram] Set default compressor to LZ4"
fi

echo "/* $MARKER */" >> "$ZRAM"
echo "[09-zram] Done"
