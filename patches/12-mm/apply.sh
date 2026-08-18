#!/usr/bin/env bash
# Patch 12: Memory Management Tuning
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_MM_PATCHED"
PATCHED=0

# 1. Change default swappiness to 100 in vmscan.c
VMSCAN="${KDIR}/mm/vmscan.c"
if [ -f "$VMSCAN" ] && ! grep -q "$MARKER" "$VMSCAN" 2>/dev/null; then
    # Look for the default swappiness definition
    sed -i 's/int vm_swappiness = .*;/int vm_swappiness = 100;  /* Infinity Kernel: more aggressive swap *//' "$VMSCAN"
    echo "[12-mm] Set default swappiness to 100"
    echo "/* $MARKER */" >> "$VMSCAN"
    PATCHED=1
fi

# 2. Fix memcg swappiness in memcontrol.c
MEMCTRL="${KDIR}/mm/memcontrol.c"
if [ -f "$MEMCTRL" ] && ! grep -q "$MARKER" "$MEMCTRL" 2>/dev/null; then
    # Ensure memcg swappiness inherits properly from global
    if grep -q "mem_cgroup_swappiness" "$MEMCTRL" 2>/dev/null; then
        sed -i '/mem_cgroup_swappiness/{
            /if.*swappiness.*<.*0/i\
		/* Infinity Kernel: inherit global swappiness if unset */\
		if (memcg->swappiness == 0)\
			memcg->swappiness = vm_swappiness;
        }' "$MEMCTRL"
        echo "[12-mm] Fixed memcg swappiness inheritance"
    fi
    echo "/* $MARKER */" >> "$MEMCTRL"
    PATCHED=1
fi

if [ $PATCHED -eq 0 ]; then
    echo "[12-mm] MM files not found, skipping"
fi

echo "[12-mm] Done"
