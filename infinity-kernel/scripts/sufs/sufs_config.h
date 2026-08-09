/*
 * Infinity Kernel - SUFS (Simple Union File System) Configuration
 *
 * SUFS provides:
 * - OverlayFS for Magisk/KernelSU systemless modifications
 * - SquashFS for compressed read-only filesystem mounts
 * - Union mounting capabilities for root manager overlays
 *
 * This header defines SUFS-specific parameters and constants
 * used by the Infinity Kernel SUFS integration layer.
 *
 * Copyright (c) 2024 Infinity Kernel Project
 * Licensed under GNU GPL v2.0
 */

#ifndef __INFINITY_SUFS_CONFIG_H
#define __INFINITY_SUFS_CONFIG_H

/* SUFS Feature Flags */
#define INFINITY_SUFS_OVERLAY     (1 << 0)  /* OverlayFS support */
#define INFINITY_SUFS_SQUASHFS    (1 << 1)  /* SquashFS decompression */
#define INFINITY_SUFS_BIND_MOUNT  (1 << 2)  /* Bind mount helpers */
#define INFINITY_SUFS_STALE_READ  (1 << 3)  /* Stale read detection */
#define INFINITY_SUFS_COPY_UP     (1 << 4)  /* Copy-up on write */

/* OverlayFS tunables */
#define INFINITY_OVERLAY_REDIRECT_ALWAYS  0  /* Always follow redirects */
#define INFINITY_OVERLAY_INDEX            1  /* Enable inodes index */
#define INFINITY_OVERLAY_METACOPY         1  /* Enable metadata copy */

/* SquashFS decompression parallelism */
#define INFINITY_SQUASHFS_DECOMP_THREADS  2  /* Per-CPU decompression */
#define INFINITY_SQUASHFS_MAX_CACHE_SIZE  (64 * 1024)  /* 64KB cache */

/* Supported compression algorithms */
enum infinity_squashfs_comp {
	SQUASHFS_COMP_ZLIB   = 0,
	SQUASHFS_COMP_LZ4    = 1,
	SQUASHFS_COMP_LZO    = 2,
	SQUASHFS_COMP_XZ     = 3,
	SQUASHFS_COMP_ZSTD   = 4,
	SQUASHFS_COMP_NONE   = 5,
};

/* Default compression for Infinity Kernel */
#define INFINITY_DEFAULT_SQUASHFS_COMP  SQUASHFS_COMP_ZSTD

/* SUFS sysfs path */
#define INFINITY_SUFS_SYSFS_PATH "/sys/fs/infinity_sufs"

/* SUFS mount options for root managers */
#define SUFS_MAGISK_MOUNT_OPTS   "lowerdir=/system,upperdir=/data/adb/magisk/upper,workdir=/data/adb/magisk/work"
#define SUFS_KSU_MOUNT_OPTS      "lowerdir=/system,upperdir=/data/adb/ksu/upper,workdir=/data/adb/ksu/work"
#define SUFS_APATCH_MOUNT_OPTS   "lowerdir=/system,upperdir=/data/adb/ap/upper,workdir=/data/adb/ap/work"

#endif /* __INFINITY_SUFS_CONFIG_H */