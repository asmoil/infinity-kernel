# AnyKernel3 Ramdisk Mod Script
## Infinity Kernel for POCO X3 Pro (vayu/bhima)
## Based on AnyKernel3 by osm0sis @ xda-developers
##
## KernelSU Next + Infinity Optimizations (Linux 4.14)
## Android 13-16 | HyperOS / MIUI / Custom ROM

properties() { '
kernel.string=Infinity Kernel for POCO X3 Pro by LawRun
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
BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;
NO_BLOCK_DISPLAY=1;

. tools/ak3-core.sh;

ui_print " ";
ui_print "╔══════════════════════════════════════╗";
ui_print "║  Infinity Kernel v1.0.48              ║";
ui_print "║  POCO X3 Pro (vayu)  ·  Android 13-16 ║";
ui_print "║  KernelSU Next + SuSFS v2.1.0         ║";
ui_print "╚══════════════════════════════════════╝";
ui_print " ";

ui_print "┌─ System Detection ─────────────────────";

API=$(getprop ro.build.version.sdk 2>/dev/null);
[ -z "$API" ] && abort "Cannot read Android API. Aborting.";

if   [ "$API" -ge 36 ]; then
  ANDROID_VER="Android 16"; ui_print "│  Android: 16  (API $API)";
elif [ "$API" -ge 35 ]; then
  ANDROID_VER="Android 15"; ui_print "│  Android: 15  (API $API)";
elif [ "$API" -ge 34 ]; then
  ANDROID_VER="Android 14"; ui_print "│  Android: 14  (API $API)";
elif [ "$API" -ge 33 ]; then
  ANDROID_VER="Android 13"; ui_print "│  Android: 13  (API $API)";
else
  abort "Android 12 or lower is NOT supported. Aborting.";
fi;

TURBO_VER=$(getprop ro.mi.turboos.version.name  2>/dev/null);
HYPER_VER=$(getprop ro.mi.os.version.name        2>/dev/null);
MIUI_VER=$(getprop  ro.miui.version.code_time    2>/dev/null);

if   [ -n "$TURBO_VER" ]; then
  ROM_TYPE="TurboOS"; ui_print "│  ROM:     TurboOS $TURBO_VER";
elif [ -n "$HYPER_VER" ]; then
  ROM_TYPE="HyperOS"; ui_print "│  ROM:     HyperOS $HYPER_VER";
elif [ -n "$MIUI_VER" ];  then
  ROM_TYPE="MIUI";    ui_print "│  ROM:     MIUI";
else
  FLAVOR=$(getprop ro.build.flavor 2>/dev/null);
  ROM_TYPE="Custom";  ui_print "│  ROM:     Custom ($FLAVOR)";
fi;

if   [ "$SLOT" = "_a" ]; then
  ui_print "│  Slot:    _a  →  flashing  boot_a";
elif [ "$SLOT" = "_b" ]; then
  ui_print "│  Slot:    _b  →  flashing  boot_b";
else
  ui_print "│  Slot:    (none)";
fi;
ui_print "│  Block:   $BLOCK";
ui_print "│  Ramdisk: auto-detect";
CURRENT=$(uname -r 2>/dev/null);
ui_print "│  Current: $CURRENT";
ui_print "└────────────────────────────────────────";
ui_print " ";

ui_print "┌─ Flashing boot${SLOT} ────────────────────";
dump_boot;
write_boot;
ui_print "│  Done.";
ui_print "└────────────────────────────────────────";

ui_print " ";
ui_print "╔══════════════════════════════════════╗";
ui_print "║  Flash complete!                      ║";
ui_print "╠══════════════════════════════════════╣";
ui_print "║  ROM:     $ROM_TYPE";
ui_print "║  Android: $ANDROID_VER";
ui_print "║  Slot:    $SLOT  →  boot${SLOT}";
ui_print "╠══════════════════════════════════════╣";
ui_print "║  1. Reboot to system                  ║";
ui_print "║  2. Install KernelSU Next app:        ║";
ui_print "║     github.com/KernelSU-Next/KernelSU ║";
ui_print "║  3. SuSFS activates automatically     ║";
ui_print "╚══════════════════════════════════════╝";
ui_print " ";
## end boot install