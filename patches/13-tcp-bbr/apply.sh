#!/usr/bin/env bash
# Patch 13: TCP BBR as Default Congestion Control
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_TCP_BBR_PATCHED"
KCONF="${KDIR}/net/ipv4/Kconfig"

if [ -f "$KCONF" ] && ! grep -q "$MARKER" "$KCONF" 2>/dev/null; then
    # Ensure TCP_CONG_BBR is available
    if ! grep -q 'config TCP_CONG_BBR' "$KCONF" 2>/dev/null; then
        cat >> "$KCONF" << 'BEOF'

config TCP_CONG_BBR
	tristate "BBR TCP"
	default y
	depends on TCP_CONG_ADVANCED
	select TCP_CONG_CUBIC
	help
	  Bottleneck Bandwidth and Round-trip propagation time (BBR).
	  A model-based congestion control algorithm that aims to maximize
	  throughput while keeping queueing delays low.

	  If unsure, say Y.
BEOF
        echo "[13-tcp-bbr] Added BBR Kconfig entry"
    fi

    # Set BBR as default
    sed -i 's/DEFAULT_TCP_CONG=".*"/DEFAULT_TCP_CONG="bbr"/' "$KCONF"
    echo "[13-tcp-bbr] Set DEFAULT_TCP_CONG=\"bbr\""

    echo "/* $MARKER */" >> "$KCONF"
fi

echo "[13-tcp-bbr] Done"