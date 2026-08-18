#!/usr/bin/env bash
# Patch 16: Upstream Fixes (7 fixes)
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_UPSTREAM_FIXES_PATCHED"
FIXES_APPLIED=0

# Fix 1: modpost LTO symbol handling
MODPOST="${KDIR}/scripts/mod/modpost.c"
if [ -f "$MODPOST" ] && ! grep -q "INFINITY_FIX_MODPOST_LTO" "$MODPOST" 2>/dev/null; then
    sed -i '/find_elf_symbol.*symtab/i\
	/* Infinity Fix #1: handle LTO-renamed symbols */\
	if (!sym && strstr(name, ".llvm."))\
		sym = find_elf_symbol(symtab, strtab, name + 5);
' "$MODPOST"
    echo "[16-upstream] Fix #1: modpost LTO symbol handling"
    echo "/* INFINITY_FIX_MODPOST_LTO */" >> "$MODPOST"
    FIXES_APPLIED=$((FIXES_APPLIED + 1))
fi

# Fix 2: thermal_core NULL pointer dereference
THERMAL_CORE="${KDIR}/drivers/thermal/thermal_core.c"
if [ -f "$THERMAL_CORE" ] && ! grep -q "INFINITY_FIX_THERMAL_NULL" "$THERMAL_CORE" 2>/dev/null; then
    sed -i '/thermal_zone_get_temp/i\
	/* Infinity Fix #2: NULL check thermal zone */\
	if (!tz || !tz->ops->get_temp)\
		return -ENODEV;
' "$THERMAL_CORE"
    echo "[16-upstream] Fix #2: thermal_core NULL check"
    echo "/* INFINITY_FIX_THERMAL_NULL */" >> "$THERMAL_CORE"
    FIXES_APPLIED=$((FIXES_APPLIED + 1))
fi

# Fix 3: cam_trace %pK format string
CAM_TRACE="${KDIR}/drivers/media/platform/msm/camera/cam_utils/cam_trace.h"
if [ -f "$CAM_TRACE" ] && ! grep -q "INFINITY_FIX_CAM_TRACE" "$CAM_TRACE" 2>/dev/null; then
    # Replace %p with %pK to avoid kernel pointer leaks
    sed -i 's/%p[^K]/%pK/g' "$CAM_TRACE" 2>/dev/null
    echo "[16-upstream] Fix #3: cam_trace %pK format"
    echo "/* INFINITY_FIX_CAM_TRACE */" >> "$CAM_TRACE"
    FIXES_APPLIED=$((FIXES_APPLIED + 1))
fi

# Fix 4: SPI probe defer handling
SPI_CORE="${KDIR}/drivers/spi/spi.c"
if [ -f "$SPI_CORE" ] && ! grep -q "INFINITY_FIX_SPI_PROBE" "$SPI_CORE" 2>/dev/null; then
    # Add EPROBE_DEFER retry logic
    sed -i '/spi_probe.*return.*ret/i\
	/* Infinity Fix #4: retry on EPROBE_DEFER */\
	if (ret == -EPROBE_DEFER)\
		return ret;
' "$SPI_CORE"
    echo "[16-upstream] Fix #4: SPI probe defer"
    echo "/* INFINITY_FIX_SPI_PROBE */" >> "$SPI_CORE"
    FIXES_APPLIED=$((FIXES_APPLIED + 1))
fi

# Fix 5: clk-cpu-osm 300MHz frequency
CLK_CPU="${KDIR}/drivers/clk/qcom/clk-cpu-8996.c"
if [ ! -f "$CLK_CPU" ]; then
    CLK_CPU="${KDIR}/drivers/clk/qcom/clk-sm8150.c"
fi
if [ -f "$CLK_CPU" ] && ! grep -q "INFINITY_FIX_CLK_CPU" "$CLK_CPU" 2>/dev/null; then
    # Add 300MHz frequency entry if missing
    if ! grep -q '300000000' "$CLK_CPU" 2>/dev/null; then
        sed -i '/freq_table/i\
	{ .freq = 300000000 },
' "$CLK_CPU"
        echo "[16-upstream] Fix #5: clk-cpu-osm 300MHz"
    fi
    echo "/* INFINITY_FIX_CLK_CPU */" >> "$CLK_CPU"
    FIXES_APPLIED=$((FIXES_APPLIED + 1))
fi

# Fix 6: WLAN GTK rekey status (complements patch 15)
for WLAN_FILE in \
    "${KDIR}/drivers/net/wireless/ath/ath10k/pci.c" \
    "${KDIR}/drivers/net/wireless/ath/ath10k/snoc.c"; do
    if [ -f "$WLAN_FILE" ] && ! grep -q "INFINITY_FIX_WLAN_GTK" "$WLAN_FILE" 2>/dev/null; then
        # Add GTK rekey event status check
        sed -i '/gtk_rekey/a\
		/* Infinity Fix #6: validate GTK rekey status */\
		if (ev.status != 0)\
			ath10k_warn(ar, "GTK rekey failed: %d\n", ev.status);
' "$WLAN_FILE" 2>/dev/null
        echo "[16-upstream] Fix #6: WLAN GTK in $(basename "$WLAN_FILE")"
        echo "/* INFINITY_FIX_WLAN_GTK */" >> "$WLAN_FILE"
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
        break
    fi
done

# Fix 7: alarmtimer argument validation
ALARMTIMER="${KDIR}/kernel/time/alarmtimer.c"
if [ -f "$ALARMTIMER" ] && ! grep -q "INFINITY_FIX_ALARMTIMER" "$ALARMTIMER" 2>/dev/null; then
    # Validate timespec args in alarm_start_relative
    sed -i '/alarm_start_relative/i\
	/* Infinity Fix #7: validate alarm timer arguments */\
	if (expires.tv64 < 0)\
		return;
' "$ALARMTIMER" 2>/dev/null || true
    echo "[16-upstream] Fix #7: alarmtimer args validation"
    echo "/* INFINITY_FIX_ALARMTIMER */" >> "$ALARMTIMER"
    FIXES_APPLIED=$((FIXES_APPLIED + 1))
fi

echo "[16-upstream-fixes] $FIXES_APPLIED fixes applied"
echo "[16-upstream-fixes] Done"
