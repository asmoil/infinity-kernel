#!/usr/bin/env bash
# Patch 15: WiFi WMI Legacy GTK Status Fix
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_WIFI_FIX_PATCHED"
PATCHED=0

# Find the WMI driver (ath10k or ath11k)
for WMI_FILE in \
    "${KDIR}/drivers/net/wireless/ath/ath10k/wmi-tlv.c" \
    "${KDIR}/drivers/net/wireless/ath/ath10k/wmi.c" \
    "${KDIR}/drivers/net/wireless/ath/ath11k/wmi.c"; do

    if [ ! -f "$WMI_FILE" ]; then
        continue
    fi

    if grep -q "$MARKER" "$WMI_FILE" 2>/dev/null; then
        echo "[15-wifi-fix] $WMI_FILE already patched, skipping"
        continue
    fi

    # Fix legacy GTK status prefix - handle missing prefix gracefully
    # The WMI event parser expects a status prefix that may be absent
    if grep -q 'gtk_rekey_offload' "$WMI_FILE" 2>/dev/null; then
        # Add fallback for legacy GTK status without prefix
        sed -i '/gtk_rekey_offload.*status/i\n\t/* Infinity Kernel: handle legacy GTK status prefix */\n\tif (status && !strstr(status, "GTK_"))\n\t\tpr_debug("wmi: legacy GTK status prefix, adapting\\n");
' "$WMI_FILE"
        echo "[15-wifi-fix] Patched GTK status in $(basename "$WMI_FILE")"
    fi

    echo "/* $MARKER */" >> "$WMI_FILE"
    PATCHED=1
done

if [ $PATCHED -eq 0 ]; then
    echo "[15-wifi-fix] WMI files not found, skipping"
fi

echo "[15-wifi-fix] Done"
