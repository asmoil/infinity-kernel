### AnyKernel3 Ramdisk Mod Script
## TurboOS KSU+SUSFS for POCO X3 Pro (vayu/bhima)
## Based on AnyKernel3 by osm0sis @ xda-developers
##
## KernelSU Next + SUSFS 1.5.5 MOD legacy (Linux 4.14)
## Android 13–16 | HyperOS / TurboOS / MIUI / Custom ROM

# ================================================================
# === AnyKernel properties (checked BEFORE any shell runs)     ===
# ================================================================
properties() { '
kernel.string=TurboOS KSU+SUSFS Kernel for POCO X3 Pro by LawRun
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=vayu
device.name2=bhima
device.name3=
device.name4=
device.name5=
supported.versions=13-16
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

# ================================================================
# === Boot ramdisk file permissions                            ===
# ================================================================
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# ================================================================
# === Core variables (set BEFORE importing ak3-core.sh)        ===
# ================================================================
# Use short name — find_block() will resolve the full path
# (tries /dev/block/mapper, /dev/block/by-name,
#        /dev/block/bootdevice/by-name, all with $SLOT appended)
BLOCK=boot;

# IS_SLOT_DEVICE=1 → ak3-core.sh reads ro.boot.slot_suffix
# (or /proc/cmdline) and sets $SLOT = _a or _b automatically.
IS_SLOT_DEVICE=1;

# Let magiskboot choose the best compression for this ramdisk.
RAMDISK_COMPRESSION=auto;

# auto = disable AVB verification only if it would block the flash.
# On unlocked HyperOS/TurboOS vbmeta is already patched by
# fastboot → this flag does nothing. NEVER touches dtbo.
PATCH_VBMETA_FLAG=auto;

# Suppress the default "ui_print <block_path>" inside setup_ak;
# we print our own styled output after the import.
NO_BLOCK_DISPLAY=1;

# ================================================================
# === Import AnyKernel3 core  (calls setup_ak internally)      ===
# ===                                                          ===
# === After this line:                                         ===
# ===   $SLOT  = "_a" | "_b"  (active slot, current boot)     ===
# ===   $BLOCK = full resolved block path, e.g.               ===
# ===            /dev/block/bootdevice/by-name/boot_a         ===
# ================================================================
. tools/ak3-core.sh;

# ================================================================
# === BANNER                                                   ===
# ================================================================
ui_print " ";
ui_print "╔══════════════════════════════════════╗";
ui_print "║  TurboOS KSU + SUSFS Kernel          ║";
ui_print "║  POCO X3 Pro (vayu)  ·  A13–A16      ║";
ui_print "║  KernelSU Next + SUSFS 1.5.5 MOD     ║";
ui_print "╚══════════════════════════════════════╝";
ui_print " ";

# ================================================================
# === AUTO-DETECTION                                           ===
# ================================================================
ui_print "┌─ System Detection ─────────────────────";

# ── Android API level ──────────────────────────────────────────
API=$(getprop ro.build.version.sdk 2>/dev/null);
[ -z "$API" ] && abort "Cannot read Android API. Aborting.";

if   [ "$API" -ge 36 ]; then
  ANDROID_VER="Android 16"; ui_print "│  Android: 16  (API $API)  ✓";
elif [ "$API" -ge 35 ]; then
  ANDROID_VER="Android 15"; ui_print "│  Android: 15  (API $API)  ✓";
elif [ "$API" -ge 34 ]; then
  ANDROID_VER="Android 14"; ui_print "│  Android: 14  (API $API)  ✓";
elif [ "$API" -ge 33 ]; then
  ANDROID_VER="Android 13"; ui_print "│  Android: 13  (API $API)  ✓";
else
  abort "Android 12 or lower is NOT supported. Aborting.";
fi;

# ── ROM detection ──────────────────────────────────────────────
TURBO_VER=$(getprop ro.mi.turboos.version.name  2>/dev/null);
HYPER_VER=$(getprop ro.mi.os.version.name        2>/dev/null);
MIUI_VER=$(getprop  ro.miui.version.code_time    2>/dev/null);

if   [ -n "$TURBO_VER" ]; then
  ROM_TYPE="TurboOS"; ui_print "│  ROM:     TurboOS $TURBO_VER  ✓";
elif [ -n "$HYPER_VER" ]; then
  ROM_TYPE="HyperOS"; ui_print "│  ROM:     HyperOS $HYPER_VER  ✓";
elif [ -n "$MIUI_VER" ];  then
  ROM_TYPE="MIUI";    ui_print "│  ROM:     MIUI  ✓";
else
  FLAVOR=$(getprop ro.build.flavor 2>/dev/null);
  ROM_TYPE="Custom";  ui_print "│  ROM:     Custom ($FLAVOR)  ✓";
fi;

# ── Slot display ($SLOT already resolved by ak3-core.sh) ───────
# At this point $SLOT = "_a" or "_b" (set inside setup_ak above).
# $BLOCK is the full resolved path, e.g.:
#   /dev/block/bootdevice/by-name/boot_a
#   /dev/block/bootdevice/by-name/boot_b
if   [ "$SLOT" = "_a" ]; then
  ui_print "│  Slot:    _a  →  flashing  boot_a  ✓";
elif [ "$SLOT" = "_b" ]; then
  ui_print "│  Slot:    _b  →  flashing  boot_b  ✓";
else
  ui_print "│  Slot:    (none — A-only device)";
fi;
ui_print "│  Block:   $BLOCK";

# ── Ramdisk compression ────────────────────────────────────────
ui_print "│  Ramdisk: auto-detect  ✓";

# ── Kernel being flashed ───────────────────────────────────────
CURRENT=$(uname -r 2>/dev/null);
ui_print "│  Current: $CURRENT";

ui_print "└────────────────────────────────────────";
ui_print " ";

# ================================================================
# === PARTITION SAFETY TABLE                                   ===
# ================================================================
ui_print "┌─ Partition plan ───────────────────────";
ui_print "│  boot${SLOT}  →  FLASH  ✓  (new kernel)";
ui_print "│  dtbo         →  SKIP   ✓  (Xiaomi HW overlays)";
ui_print "│  vbmeta       →  SKIP   ✓  (already patched by fastboot)";
ui_print "│  vendor_boot  →  SKIP   ✓";
ui_print "│  init_boot    →  SKIP   ✓";
ui_print "└────────────────────────────────────────";
ui_print " ";
#
# WHY dtbo is NOT touched:
#   Image.gz-dtb already contains the SM8150 base device tree.
#   The dtbo partition holds Xiaomi-signed hardware overlays
#   (touch calibration, display panel ID, camera sensor config).
#   Overwriting dtbo can break touch / display on HyperOS/TurboOS.
#   The kernel does NOT need a custom dtbo to run KSU+SUSFS.
#
# WHY vbmeta is NOT touched:
#   Unlocking the bootloader already disables AVB verification
#   on HyperOS/TurboOS (fastboot --disable-verity).
#   PATCH_VBMETA_FLAG=auto only acts when dm-verity is actively
#   blocking the flash — on an unlocked device it does nothing.

# ================================================================
# === SUSFS SAFETY PROFILE (vayu-specific)                    ===
# ================================================================
ui_print "┌─ SUSFS config  (vayu / SM8150 / 4.14) ─";
ui_print "│  sus_mount    →  ON   ✓  (mount namespace hiding)";
ui_print "│  sus_overlay  →  ON   ✓  (overlay FS hiding)";
ui_print "│  magic_mount  →  ON   ✓  (module file overlay)";
ui_print "│  sus_su       →  OFF  ✓  (inline hook — panic on 4.14)";
ui_print "│  uid spoof    →  OFF  ✓  (unstable on SM8150)";
ui_print "│  proc spoof   →  OFF  ✓  (SELinux AVC cascade)";
ui_print "└────────────────────────────────────────";
ui_print " ";

# ================================================================
# === FLASH                                                    ===
# ================================================================
ui_print "┌─ Flashing boot${SLOT} ───────────────────────";

# Unpack the current boot image, inject new kernel + ramdisk overlay
dump_boot;

# ramdisk/overlay.d/10_kernelsu/ is packed into the boot ramdisk
# by AnyKernel3 automatically — no manual copy needed.
# Contents:
#   post-fs-data.sh  → KSU props, SUSFS modes, BBR, zRAM, schedutil
#   service.sh       → KSU module enable, WireGuard check

# Repack and write ONLY boot${SLOT} — dtbo/vbmeta are never called
write_boot;

ui_print "│  Done.";
ui_print "└────────────────────────────────────────";

# ================================================================
# === SUMMARY                                                  ===
# ================================================================
ui_print " ";
ui_print "╔══════════════════════════════════════╗";
ui_print "║  Flash complete!                      ║";
ui_print "╠══════════════════════════════════════╣";
ui_print "║  ROM:     $ROM_TYPE";
ui_print "║  Android: $ANDROID_VER";
ui_print "║  Slot:    $SLOT  →  boot${SLOT}";
ui_print "╠══════════════════════════════════════╣";
ui_print "║  Next steps:                          ║";
ui_print "║  1. Reboot to system                  ║";
ui_print "║  2. Install KernelSU Next app:        ║";
ui_print "║     github.com/KernelSU-Next/KernelSU ║";
ui_print "║  3. SUSFS activates automatically     ║";
ui_print "╚══════════════════════════════════════╝";
ui_print " ";
## end boot install
