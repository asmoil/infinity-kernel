### AnyKernel3 Ramdisk Mod Script
## Infinity Kernel for Poco X3 Pro (vayu/bhima)

### AnyKernel setup
# global properties
properties() { '
kernel.string=Infinity Kernel by InfinityTeam
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
supported.versions=11 - 17
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $ramdisk/*;
set_perm_recursive 0 0 750 750 $ramdisk/init* $ramdisk/sbin;
} # end attributes

# boot shell variables
block=auto;
is_slot_device=0;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
dump_boot;

# ============================================================================
# Root Manager Detection & Compatibility
# ============================================================================
# Detects: KernelSU, KernelSU Next, APatch, Magisk, ReSukiSu, SukiSU Ultra
# Ensures proper boot.img handling for each manager's module format.
# ============================================================================

ui_print " ";
ui_print "=== Root Manager Detection ===";

# -- KernelSU (original by tiann) --
# Path: /data/adb/ksu  or  /data/data/me.weishu.kernelsu
# Module image: /data/adb/ksu/modules.img
# ksud binary: /data/adb/ksud
if [ -d /data/adb/ksu ] || [ -f /data/adb/ksud ] || [ -d /data/data/me.weishu.kernelsu ]; then
    ui_print "  [+] KernelSU detected";
    if [ -f /data/adb/ksud ]; then
        KSU_VER=$(/data/adb/ksud --version 2>/dev/null | head -1);
        ui_print "      Version: $KSU_VER";
    fi
    # Ensure KSU module image exists for systemless module install
    if [ -d /data/adb/ksu ] && [ ! -f /data/adb/ksu/modules.img ]; then
        ui_print "      Creating KernelSU modules.img ...";
        /system/bin/make_ext4fs -b 1024 -l 256M /data/adb/ksu/modules.img 2>/dev/null \
            || /system/bin/mke2fs -b 1024 -t ext4 /data/adb/ksu/modules.img 256M 2>/dev/null;
    fi
    ROOT_MGR_DETECTED=1;
    ROOT_MGR_NAME="KernelSU";
fi

# -- KernelSU Next (fork by us18n) --
# Path: /data/adb/ksu  (same as KSU, but with different ksud behavior)
# Identified by ksud --version output containing "next" or "Next"
if [ -f /data/adb/ksud ]; then
    KSU_NEXT_CHECK=$(/data/adb/ksud --version 2>/dev/null | grep -i "next");
    if [ -n "$KSU_NEXT_CHECK" ]; then
        ui_print "  [+] KernelSU Next detected";
        ui_print "      $KSU_NEXT_CHECK";
        ROOT_MGR_DETECTED=1;
        ROOT_MGR_NAME="KernelSU Next";
    fi
fi

# -- APatch (by bmax121) --
# Path: /data/adb/ap  or  /data/adb/apatch
# Module image: /data/adb/ap/modules.img
# Manager: /data/adb/apd
if [ -d /data/adb/ap ] || [ -d /data/adb/apatch ] || [ -f /data/adb/apd ]; then
    ui_print "  [+] APatch detected";
    if [ -f /data/adb/apd ]; then
        APATCH_VER=$(/data/adb/apd --version 2>/dev/null | head -1);
        ui_print "      Version: $APATCH_VER";
    fi
    # Ensure APatch module image exists
    AP_MOD_DIR="/data/adb/ap"
    [ -d /data/adb/apatch ] && AP_MOD_DIR="/data/adb/apatch"
    if [ ! -f "$AP_MOD_DIR/modules.img" ]; then
        ui_print "      Creating APatch modules.img ...";
        /system/bin/make_ext4fs -b 1024 -l 256M "$AP_MOD_DIR/modules.img" 2>/dev/null \
            || /system/bin/mke2fs -b 1024 -t ext4 "$AP_MOD_DIR/modules.img" 256M 2>/dev/null;
    fi
    ROOT_MGR_DETECTED=1;
    ROOT_MGR_NAME="APatch";
fi

# -- Magisk (by topjohnwu) --
# Path: /data/adb/magisk
# Binary: /data/adb/magisk/magisk32 or magisk64
if [ -d /data/adb/magisk ]; then
    ui_print "  [+] Magisk detected";
    if [ -f /data/adb/magisk/magisk64 ]; then
        MAGISK_VER=$(/data/adb/magisk/magisk64 -v 2>/dev/null | head -1);
        MAGISK_CODE=$(/data/adb/magisk/magisk64 -V 2>/dev/null);
        ui_print "      Version: $MAGISK_VER ($MAGISK_CODE)";
    elif [ -f /data/adb/magisk/magisk32 ]; then
        MAGISK_VER=$(/data/adb/magisk/magisk32 -v 2>/dev/null | head -1);
        ui_print "      Version: $MAGISK_VER";
    fi
    ROOT_MGR_DETECTED=1;
    ROOT_MGR_NAME="Magisk";
fi

# -- ReSukiSu --
# Path: /data/adb/resukisu  or  /data/adb/re_sukisu
# Uses KernelSU-compatible module structure
if [ -d /data/adb/resukisu ] || [ -d /data/adb/re_sukisu ]; then
    ui_print "  [+] ReSukiSu detected";
    RESUKISU_DIR="/data/adb/resukisu"
    [ -d /data/adb/re_sukisu ] && RESUKISU_DIR="/data/adb/re_sukisu"
    # Ensure module image
    if [ ! -f "$RESUKISU_DIR/modules.img" ]; then
        ui_print "      Creating ReSukiSu modules.img ...";
        /system/bin/make_ext4fs -b 1024 -l 256M "$RESUKISU_DIR/modules.img" 2>/dev/null \
            || /system/bin/mke2fs -b 1024 -t ext4 "$RESUKISU_DIR/modules.img" 256M 2>/dev/null;
    fi
    ROOT_MGR_DETECTED=1;
    ROOT_MGR_NAME="ReSukiSu";
fi

# -- SukiSU Ultra --
# Path: /data/adb/sukisu  or  /data/adb/sukisu_ultra
# Uses KernelSU-compatible module structure
if [ -d /data/adb/sukisu ] || [ -d /data/adb/sukisu_ultra ]; then
    ui_print "  [+] SukiSU Ultra detected";
    SUKISU_DIR="/data/adb/sukisu"
    [ -d /data/adb/sukisu_ultra ] && SUKISU_DIR="/data/adb/sukisu_ultra"
    # Ensure module image
    if [ ! -f "$SUKISU_DIR/modules.img" ]; then
        ui_print "      Creating SukiSU Ultra modules.img ...";
        /system/bin/make_ext4fs -b 1024 -l 256M "$SUKISU_DIR/modules.img" 2>/dev/null \
            || /system/bin/mke2fs -b 1024 -t ext4 "$SUKISU_DIR/modules.img" 256M 2>/dev/null;
    fi
    ROOT_MGR_DETECTED=1;
    ROOT_MGR_NAME="SukiSU Ultra";
fi

# -- No root manager found --
if [ "$ROOT_MGR_DETECTED" != "1" ]; then
    ui_print "  [-] No root manager detected";
    ui_print "      Supported: KernelSU / KSU Next / APatch /";
    ui_print "                 Magisk / ReSukiSu / SukiSU Ultra";
    ui_print "      Kernel hooks (kprobes/ftrace/kallsyms) are";
    ui_print "      pre-enabled for seamless root setup later.";
fi

ui_print " ";

# ============================================================================
# Infinity Kernel init.rc tuning
# ============================================================================
backup_file init.rc;
replace_string init.rc "cpuctl cpu,timer_slack" "mount cgroup none /dev/cpuctl cpu" "mount cgroup none /dev/cpuctl cpu,timer_slack";

# ============================================================================
# fstab.qcom optimizations for Poco X3 Pro
# ============================================================================
backup_file fstab.qcom;
patch_fstab fstab.qcom /vendor ext4 options "barrier=1" "barrier=0,nomblk_io_submit";
patch_fstab fstab.qcom /system ext4 options "barrier=1" "barrier=0";

# ============================================================================
# MIUI DSI compatibility patch
# ============================================================================
. $bin/kyriepatch.sh;

write_boot;
## end boot install


## init_boot files attributes
#init_boot_attributes() {
#set_perm_recursive 0 0 755 644 $ramdisk/*;
#set_perm_recursive 0 0 750 750 $ramdisk/init* $ramdisk/sbin;
#} # end attributes

# init_boot shell variables
#block=init_boot;
#is_slot_device=1;
#ramdisk_compression=auto;
#patch_vbmeta_flag=auto;

# reset for init_boot patching
#reset_ak;

# init_boot install
#dump_boot;

#write_boot;
## end init_boot install


## vendor_kernel_boot shell variables
#block=vendor_kernel_boot;
#is_slot_device=1;
#ramdisk_compression=auto;
#patch_vbmeta_flag=auto;

# reset for vendor_kernel_boot patching
#reset_ak;

# vendor_kernel_boot install
#split_boot;

#flash_boot;
## end vendor_kernel_boot install


## vendor_boot files attributes
#vendor_boot_attributes() {
#set_perm_recursive 0 0 755 644 $ramdisk/*;
#set_perm_recursive 0 0 750 750 $ramdisk/init* $ramdisk/sbin;
#} # end attributes

# vendor_boot shell variables
#block=vendor_boot;
#is_slot_device=1;
#ramdisk_compression=auto;
#patch_vbmeta_flag=auto;

# reset for vendor_boot patching
#reset_ak;

# vendor_boot install
#dump_boot;

#write_boot;
## end vendor_boot install