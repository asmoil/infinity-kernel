#!/usr/bin/env bash
# Patch 01: SUSFS Integration
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=susfs_tag $3=root_type

KDIR="$1"
SUSFS_TAG="$2"
ROOT_TYPE="$3"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> <susfs_tag> <root_type>"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

# Only integrate for supported root types
case "$ROOT_TYPE" in
    kernelsu|apatch) ;;
    *)
        echo "[01-susfs] SUSFS not needed for '$ROOT_TYPE', skipping"
        exit 0
        ;;
esac

SUSFS_DIR="${KDIR}/susfs"
if [ -d "$SUSFS_DIR" ]; then
    echo "[01-susfs] SUSFS already exists, skipping clone"
else
    echo "[01-susfs] Cloning SUSFS (tag: $SUSFS_TAG)..."
    git clone --depth=1 -b "$SUSFS_TAG" \
        https://github.com/vm03/susfs "$SUSFS_DIR"
fi

# Write config fragment
CONF="${KDIR}/arch/arm64/configs/infinity_susfs.config"
echo "[01-susfs] Writing config fragment to $CONF"
cat > "$CONF" << 'SUSFS_EOF'
CONFIG_SUSFS=y
CONFIG_SUSFS_SUS_PATH=y
CONFIG_SUSFS_SUS_MOUNT=y
CONFIG_SUSFS_TRY_UMOUNT=y
CONFIG_SUSFS_SPOOF_UNLINK=y
CONFIG_SUSFS_ENABLE_LOG=y
CONFIG_SUSFS_SUS_KSTAT=y
CONFIG_SUSFS_SUS_OVERLAYFS=y
CONFIG_SUSFS_SPOOF_PROC_SELF_STATUS=y
CONFIG_SUSFS_SPOOF_PROC_CMDLINE=y
CONFIG_SUSFS_SUS_DNAME=y
CONFIG_SUSFS_SPOOF_RSTAT=y
CONFIG_SUSFS_SPOOF_ACCESS=y
CONFIG_SUSFS_SPOOF_READLINK=y
CONFIG_SUSFS_SPOOF_OPENAT2=y
CONFIG_SUSFS_SPOOF_GETDENT64=y
CONFIG_SUSFS_SUS_INODE=y
SUSFS_EOF

# Patch fs/Makefile to include susfs
if ! grep -q "susfs" "${KDIR}/fs/Makefile" 2>/dev/null; then
    echo "[01-susfs] Patching fs/Makefile"
    sed -i '/^obj-y/i obj-y += susfs/' "${KDIR}/fs/Makefile"
fi

echo "[01-susfs] SUSFS integrated"
