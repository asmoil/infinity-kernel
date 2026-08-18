#!/usr/bin/env bash
# Patch 00: KernelSU / APatch Integration
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=tag $3=root_type

KDIR="$1"
TAG="$2"
ROOT_TYPE="$3"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> <tag> <root_type>"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

case "$ROOT_TYPE" in
    kernelsu)
        KSU_DIR="${KDIR}/KernelSU-Next"
        if [ -d "$KSU_DIR" ]; then
            echo "[00-kernelsu] KernelSU-Next already exists, skipping"
        else
            echo "[00-kernelsu] Cloning KernelSU-Next (tag: $TAG)..."
            git clone --depth=1 -b "$TAG" \
                https://github.com/KernelSU-Next/kernel-su-next "$KSU_DIR"
        fi
        # Add to Makefile if not already present
        if ! grep -q "KernelSU-Next" "${KDIR}/Makefile" 2>/dev/null; then
            echo "[00-kernelsu] Adding KernelSU-Next to Makefile"
            sed -i '/^obj-y/i # KernelSU-Next\nobj-y += KernelSU-Next/' "${KDIR}/Makefile"
        fi
        echo "[00-kernelsu] KernelSU integrated"
        ;;
    apatch)
        APATCH_DIR="${KDIR}/APatch"
        if [ -d "$APATCH_DIR" ]; then
            echo "[00-kernelsu] APatch already exists, skipping"
        else
            echo "[00-kernelsu] Cloning APatch..."
            git clone --depth=1 \
                https://github.com/bmax121/APatch "$APATCH_DIR"
        fi
        if ! grep -q "APatch" "${KDIR}/Makefile" 2>/dev/null; then
            echo "[00-kernelsu] Adding APatch to Makefile"
            sed -i '/^obj-y/i # APatch\nobj-y += APatch/' "${KDIR}/Makefile"
        fi
        echo "[00-kernelsu] APatch integrated"
        ;;
    sukisu_ultra|resukisu|kowsu)
        echo "[00-kernelsu] Root type '$ROOT_TYPE' uses external module, no source integration needed"
        ;;
    none)
        echo "[00-kernelsu] No root solution selected, skipping"
        ;;
    *)
        echo "[00-kernelsu] Unknown root type: $ROOT_TYPE"
        ;;
esac
