### AnyKernel3 Ramdisk Mod Script
## Infinity Kernel for POCO X3 Pro (vayu/bhima)
## Based on AnyKernel3 by osm0sis @ xda-developers
##
## Multi-Root: KernelSU-Next, ReSukiSU, SukiSU-Ultra, KoWSu, APatch
## SuSFS v2.1.0 | Android 11-16 QPR2+ | AOSP, MIUI, HyperOS, OxygenOS

# ================================================================
# === AnyKernel properties (checked BEFORE any shell runs)     ===
# ================================================================
properties() { '
kernel.string=Infinity Kernel for POCO X3 Pro
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
supported.versions=11-16
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

# ================================================================
# === Import AnyKernel3 core  (calls setup_ak internally)      ===
# ================================================================
. tools/ak3-core.sh;

# ================================================================
# === BANNER                                                   ===
# ================================================================
ui_print " ";
ui_print "╔══════════════════════════════════════╗";
ui_print "║      Infinity Kernel v1.0.60          ║";
ui_print "║  POCO X3 Pro (vayu/bhima)             ║";
ui_print "║  SM8150 · Linux 4.14 · Neutron Clang  ║";
ui_print "║  Multi-Root · SuSFS · BBR · ZRAM      ║";
ui_print "╚══════════════════════════════════════╝";
ui_print " ";

# ================================================================
# === AUTO-DETECTION                                           ===
# ================================================================
ui_print "┌─ System Detection ─────────────────────";

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
elif [ "$API" -ge 32 ]; then
  ANDROID_VER="Android 12"; ui_print "│  Android: 12  (API $API)  ✓";
elif [ "$API" -ge 30 ]; then
  ANDROID_VER="Android 11"; ui_print "│  Android: 11  (API $API)  ✓";
else
  abort "Android $API is NOT supported. Need 11+.";
fi;

TURBO_VER=$(getprop ro.mi.turboos.version.name  2>/dev/null);
HYPER_VER=$(getprop ro.mi.os.version.name        2>/dev/null);
MIUI_VER=$(getprop  ro.miui.version.code_time    2>/dev/null);
OXYGEN_VER=$(getprop ro.oxygen.version  2>/dev/null);

if   [ -n "$TURBO_VER" ]; then
  ROM_TYPE="TurboOS"; ui_print "│  ROM:     TurboOS $TURBO_VER  ✓";
elif [ -n "$HYPER_VER" ]; then
  ROM_TYPE="HyperOS"; ui_print "│  ROM:     HyperOS $HYPER_VER  ✓";
elif [ -n "$MIUI_VER" ];  then
  ROM_TYPE="MIUI";    ui_print "│  ROM:     MIUI  ✓";
elif [ -n "$OXYGEN_VER" ]; then
  ROM_TYPE="OxygenOS"; ui_print "│  ROM:     OxygenOS  ✓";
else
  FLAVOR=$(getprop ro.build.flavor 2>/dev/null);
  ROM_TYPE="AOSP/Custom";  ui_print "│  ROM:     $FLAVOR  ✓";
fi;

if   [ "$SLOT" = "_a" ]; then
  ui_print "│  Slot:    _a  →  flashing  boot_a  ✓";
elif [ "$SLOT" = "_b" ]; then
  ui_print "│  Slot:    _b  →  flashing  boot_b  ✓";
else
  ui_print "│  Slot:    (none — A-only device)";
fi;
ui_print "│  Block:   $BLOCK";

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
ui_print "│  vbmeta       →  SKIP   ✓  (already patched)";
ui_print "│  vendor_boot  →  SKIP   ✓";
ui_print "│  init_boot    →  SKIP   ✓";
ui_print "└────────────────────────────────────────";
ui_print " ";

# ================================================================
# === FLASH                                                    ===
# ================================================================
ui_print "┌─ Flashing boot${SLOT} ───────────────────────";

dump_boot;
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
ui_print "║  Supported root solutions:            ║";
ui_print "║  · KernelSU-Next                      ║";
ui_print "║  · ReSukiSU                           ║";
ui_print "║  · SukiSU-Ultra                       ║";
ui_print "║  · KoWSu                              ║";
ui_print "║  · APatch                             ║";
ui_print "╚══════════════════════════════════════╝";
ui_print " ";
## end boot install