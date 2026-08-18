#!/usr/bin/env bash
# Patch 11: ext4 Performance Patches
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_EXT4_PATCHED"

FILE_C="${KDIR}/fs/ext4/file.c"
INODE_C="${KDIR}/fs/ext4/inode.c"

PATCHED=0

# 1. cond_resched in mb_cache_entry_find (file.c)
if [ -f "$FILE_C" ] && ! grep -q "$MARKER" "$FILE_C" 2>/dev/null; then
    # Add cond_resched in long-running loops in mb_cache_entry_find
    if grep -q "mb_cache_entry_find" "$FILE_C" 2>/dev/null; then
        sed -i '/while.*mb_cache_entry_find/{ n; /{$/a \
		cond_resched();
        }' "$FILE_C"
        echo "[11-ext4] Added cond_resched in mb_cache_entry_find"
    fi

    # 2. cond_resched in ext4_find_delalloc_range
    if grep -q "ext4_find_delalloc_range" "$FILE_C" 2>/dev/null; then
        sed -i '/while.*start.*<=.*end/{ n; /{$/a \
		cond_resched();
        }' "$FILE_C"
        echo "[11-ext4] Added cond_resched in ext4_find_delalloc_range"
    fi

    echo "/* $MARKER */" >> "$FILE_C"
    PATCHED=1
fi

# 3. fsync optimization in inode.c
if [ -f "$INODE_C" ] && ! grep -q "$MARKER" "$INODE_C" 2>/dev/null; then
    # Reduce unnecessary journal flushes on fsync
    if grep -q "ext4_sync_inode" "$INODE_C" 2>/dev/null; then
        sed -i '/ext4_sync_inode/i \
\t/* Infinity Kernel: skip journal flush if no data to commit */\
\tif (!inode->i_dirty && !ext4_test_inode_state(inode, EXT4_STATE_DA_WRITE_CLOSE))\
\t	return 0;
        ' "$INODE_C"
        echo "[11-ext4] Added fsync optimization"
    fi

    echo "/* $MARKER */" >> "$INODE_C"
    PATCHED=1
fi

if [ $PATCHED -eq 0 ]; then
    echo "[11-ext4] ext4 files not found, skipping"
fi

echo "[11-ext4] Done"