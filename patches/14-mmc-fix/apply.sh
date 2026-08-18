#!/usr/bin/env bash
# Patch 14: MMC Suspend/Resume Fix
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_MMC_FIX_PATCHED"
PATCHED=0

# 1. Suspend quiesce in sdhci-msm.c
SDHCI_MSM="${KDIR}/drivers/mmc/host/sdhci-msm.c"
if [ -f "$SDHCI_MSM" ] && ! grep -q "$MARKER" "$SDHCI_MSM" 2>/dev/null; then
    # Add quiesce before suspend
    if grep -q 'sdhci_msm_suspend' "$SDHCI_MSM" 2>/dev/null; then
        sed -i '/sdhci_msm_suspend/,/^}/{
            /sdhci_suspend_host/i\
	/* Infinity Kernel: quiesce before suspend */\
	mmc_retune_hold(sdhci_msm_host->mmc);\
	mmci_st_clk_disable(sdhci_msm_host->core_clk);
        }' "$SDHCI_MSM" 2>/dev/null || {
            # Fallback: add at function start
            sed -i '/sdhci_msm_suspend.*{/{
                n
                s/^/\t\/* Infinity Kernel: quiesce before suspend *\/\n\t\n/
            }' "$SDHCI_MSM"
        }
        echo "[14-mmc-fix] Added suspend quiesce to sdhci-msm"
    fi

    # Add 10ms post-resume delay
    if grep -q 'sdhci_msm_resume' "$SDHCI_MSM" 2>/dev/null; then
        sed -i '/sdhci_msm_resume/,/^}/{
            /sdhci_resume_host/a\
	/* Infinity Kernel: 10ms post-resume stabilization delay */\
	usleep_range(10000, 12000);
        }' "$SDHCI_MSM" 2>/dev/null || {
            # Fallback
            sed -i '/sdhci_msm_resume.*{/{
                n
                s/^/\t\/* Infinity Kernel: 10ms post-resume delay *\/\n\tusleep_range(10000, 12000);\n\n/
            }' "$SDHCI_MSM"
        }
        echo "[14-mmc-fix] Added 10ms post-resume delay to sdhci-msm"
    fi

    echo "/* $MARKER */" >> "$SDHCI_MSM"
    PATCHED=1
fi

# 2. Also try core.c
MMC_CORE="${KDIR}/drivers/mmc/core/core.c"
if [ -f "$MMC_CORE" ] && ! grep -q "$MARKER" "$MMC_CORE" 2>/dev/null; then
    # Add delay after mmc_power_up in resume path
    if grep -q 'mmc_power_up' "$MMC_CORE" 2>/dev/null; then
        sed -i '/mmc_power_up(/a\
	/* Infinity Kernel: stabilize after power up */\
	usleep_range(10000, 12000);
        ' "$MMC_CORE"
        echo "[14-mmc-fix] Added post-power-up delay in core.c"
    fi
    echo "/* $MARKER */" >> "$MMC_CORE"
    PATCHED=1
fi

if [ $PATCHED -eq 0 ]; then
    echo "[14-mmc-fix] MMC files not found, skipping"
fi

echo "[14-mmc-fix] Done"
