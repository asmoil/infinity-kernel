#!/system/bin/sh

##########################################################################################
# Infinity Kernel AnyKernel3 Flash Script v2.0
# Device: Poco X3 Pro (vayu/bhima)
# Supports: AnyKernel flash, KernelSU, KSU Next, Magisk, APatch, ReSukiSu, SukiSU Ultra
# Features: Task-Aware Engine, SUFS, Enhanced Thermal, Charging Bypass
##########################################################################################

## AnyKernel3 properties
kernel.string="Infinity Kernel for Poco X3 Pro"
kernel.forum="https://t.me/infinity_kernel"
kernel.author="InfinityKernelTeam"
kernel.version="2.0"
kernel.date="$(date '+%Y-%m-%d')"

## Device check
device.check=1
device.name1=vayu
device.name2=bhima
device.codename=vayu
device.name=vayu/bhima

## Supported Android versions
supported.versions=12,13,14

## Boot image info
block=/dev/block/bootdevice/by-name/boot;
is_slot_device=0;
do.systemless=1;
ramdisk_compression=lz4;

## Flash variables
do.devicecheck=1
do.system=0
do.cleanup=1
do.initd=0
do.modules=0
do.modpaths=0
do.skipbackup=0

##########################################################################################
# PRE-INSTALL
##########################################################################################

ui_print " "
ui_print "  ╔═══════════════════════════════════════════╗"
ui_print "  ║       INFINITY KERNEL v2.0                ║"
ui_print "  ║       Poco X3 Pro (vayu/bhima)           ║"
ui_print "  ╚═══════════════════════════════════════════╝"
ui_print " "
ui_print "  Task-Aware Performance Engine"
ui_print "  Auto-detect workload -> Adjust power"
ui_print " "
ui_print "  Features:"
ui_print "    - 9 Auto Profiles (Idle/Gaming/Media/...)"
ui_print "    - SUFS v1.5.7+ (Systemless UFS)"
ui_print "    - Multi-Stage Thermal Charging"
ui_print "    - ZRAM 5GB LZ4 (8GB RAM optimized)"
ui_print "    - 6 Root Managers Supported"
ui_print " "

# Detect root solution
ROOT_TYPE="none"
ROOT_DETECTED="none"

# KernelSU (standard)
if [ -d "/data/adb/ksu" ] || [ -f "/data/adb/ksud" ]; then
    ROOT_TYPE="KernelSU"
    ROOT_DETECTED="KernelSU"
    ui_print "  [ROOT] KernelSU detected"
fi

# KernelSU Next
if [ -d "/data/adb/ksu/modules" ] && [ -f "/data/adb/ksu/bin/ksud" ]; then
    if [ "$ROOT_TYPE" = "none" ]; then
        ROOT_TYPE="KernelSU-Next"
        ROOT_DETECTED="KernelSU Next"
        ui_print "  [ROOT] KernelSU Next detected"
    fi
fi

# Magisk
if [ -d "/data/adb/magisk" ] || [ -f "/data/adb/magisk/magisk32" ] || [ -f "/data/adb/magisk/magisk64" ]; then
    if [ "$ROOT_TYPE" = "none" ]; then
        ROOT_TYPE="Magisk"
        ROOT_DETECTED="Magisk"
        ui_print "  [ROOT] Magisk detected"
    fi
fi

# APatch
if [ -d "/data/adb/ap" ] || [ -f "/data/adb/apd" ]; then
    if [ "$ROOT_TYPE" = "none" ]; then
        ROOT_TYPE="APatch"
        ROOT_DETECTED="APatch"
        ui_print "  [ROOT] APatch detected"
    fi
fi

# ReSukiSu
if [ -d "/data/adb/resukisu" ] || [ -f "/data/adb/resukisu/resukisu" ]; then
    if [ "$ROOT_TYPE" = "none" ]; then
        ROOT_TYPE="ReSukiSu"
        ROOT_DETECTED="ReSukiSu"
        ui_print "  [ROOT] ReSukiSu detected"
    fi
fi

# SukiSU Ultra
if [ -d "/data/adb/sukisu" ] || [ -f "/data/adb/sukisu/sukisu" ] || [ -f "/data/adb/sukisu_ultra" ]; then
    if [ "$ROOT_TYPE" = "none" ]; then
        ROOT_TYPE="SukiSU-Ultra"
        ROOT_DETECTED="SukiSU Ultra"
        ui_print "  [ROOT] SukiSU Ultra detected"
    fi
fi

if [ "$ROOT_TYPE" = "none" ]; then
    ui_print "  [ROOT] No root solution detected"
    ui_print "  [ROOT] Kernel includes root manager hooks"
fi

ui_print " "
ui_print "  [CHECK] Verifying device compatibility..."

# Verify device
case "$(getprop ro.product.device)" in
    vayu|bhima)
        ui_print "  [OK] Device: $(getprop ro.product.device) confirmed"
        ;;
    *)
        ui_print "  [WARN] Device: $(getprop ro.product.device)"
        ui_print "  [WARN] This kernel is for Poco X3 Pro (vayu/bhima)!"
        ui_print "  [WARN] Flashing on wrong device may brick it!"
        ui_print " "
        ui_print "  Press Vol+ to continue anyway"
        ui_print "  Press Vol- to abort"
        if ! choose 0; then
            abort "[ABORT] Installation cancelled"
        fi
        ;;
esac

# Check Android version
ANDROID_VER=$(getprop ro.build.version.release)
ui_print "  [OK] Android $ANDROID_VER"
ui_print " "

##########################################################################################
# BACKUP
##########################################################################################

ui_print "  [BACKUP] Creating boot backup..."
backup_file="/data/local/infinity_kernel_boot_backup_$(date +%Y%m%d_%H%M%S).img"
dd if=/dev/block/bootdevice/by-name/boot of="$backup_file" 2>/dev/null
if [ $? -eq 0 ]; then
    ui_print "  [OK] Backup: $backup_file"
else
    ui_print "  [WARN] Backup failed, continuing..."
fi

ui_print " "

##########################################################################################
# FLASH KERNEL
##########################################################################################

ui_print "  [FLASH] Installing Infinity Kernel v2.0..."

# Patch boot image
[ -d "$S" ] && rm -rf "$S" 2>/dev/null
mkdir -p "$S"

# Copy kernel image
if [ -f "kernel/Image.gz-dtb" ]; then
    ui_print "  [OK] Found Image.gz-dtb"
elif [ -f "kernel/Image" ]; then
    ui_print "  [OK] Found Image"
elif [ -f "kernel/Image.lz4" ]; then
    ui_print "  [OK] Found Image.lz4"
fi

# Copy DTB/DTBO if present
if [ -d "dtb" ]; then
    ui_print "  [OK] DTB files found"
fi
if [ -f "dtbo.img" ]; then
    ui_print "  [OK] DTBO found"
fi

# Handle root solution patching
case "$ROOT_TYPE" in
    KernelSU|KernelSU-Next)
        ui_print "  [KSU] Patching for KernelSU compatibility..."
        patch_vbmeta_flag=false
        ;;
    Magisk)
        ui_print "  [MAGISK] Preserving Magisk ramdisk..."
        ;;
    APatch)
        ui_print "  [APATCH] Preserving APatch ramdisk..."
        ;;
esac

# Flash the kernel
dump_boot
write_boot

ui_print "  [OK] Kernel flashed successfully"
ui_print " "

##########################################################################################
# POST-INSTALL SETUP
##########################################################################################

ui_print "  [SETUP] Configuring Infinity Kernel v2.0..."

# Create Infinity Kernel config directory
mkdir -p /data/adb/infinity_kernel 2>/dev/null
chown -R system:system /data/adb/infinity_kernel 2>/dev/null

# ---- Charging Control Permissions ----
if [ -d "/sys/devices/platform/soc/" ]; then
    CHARGING_PATH=$(find /sys/devices/platform/soc/ -name "infinity_charging" -type d 2>/dev/null | head -1)
    if [ -n "$CHARGING_PATH" ]; then
        chown -R system:system "$CHARGING_PATH" 2>/dev/null
        chmod -R 664 "$CHARGING_PATH"/* 2>/dev/null
        ui_print "  [OK] Charging control configured"
    fi
fi

# ---- Task Engine Permissions ----
if [ -d "/sys/kernel/infinity_task_engine" ]; then
    chown -R system:system /sys/kernel/infinity_task_engine 2>/dev/null
    chmod -R 666 /sys/kernel/infinity_task_engine/* 2>/dev/null
    ui_print "  [OK] Task engine sysfs configured"
fi

# ---- Copy Task Profile Helper ----
if [ -f "tools/infinity_task_profile.sh" ]; then
    cp tools/infinity_task_profile.sh /data/adb/infinity_kernel/ 2>/dev/null
    chmod 755 /data/adb/infinity_kernel/infinity_task_profile.sh 2>/dev/null
    ui_print "  [OK] Task profile helper installed"
fi

# ---- Copy Init Script ----
if [ -f "tools/infinity_init.sh" ]; then
    # Install as post-fs-data.d service (runs early, with root)
    mkdir -p /data/adb/post-fs-data.d 2>/dev/null
    cp tools/infinity_init.sh /data/adb/post-fs-data.d/99infinity 2>/dev/null
    chmod 755 /data/adb/post-fs-data.d/99infinity 2>/dev/null
    ui_print "  [OK] Init script installed (post-fs-data.d)"
fi

# ---- Create Default Config ----
cat > /data/adb/infinity_kernel/default.conf << 'EOF'
# Infinity Kernel v2.0 Default Configuration
# Generated during kernel installation

# Task-Aware Performance Engine
task_engine_auto=true
task_engine_interval=2500
task_engine_log=true

# Charging Control — Enhanced Thermal
gaming_mode=0
max_charge_current=2500
gaming_charge_current=500
cooldown_threshold=43
resume_threshold=39
thermal_stage1=38
thermal_stage2=42
thermal_stage3=45
bypass_auto=true

# Performance Profiles
cpu_boost=true
gpu_tweaks=true
touch_boost=true

# Memory — 8GB RAM Optimized
zram_size=5120
zram_algorithm=lz4
lru_gen=true
ksm_aggressive=true
ksm_sleep_ms=500
swappiness=60

# Network
tcp_cong=bbr
tcp_bbr2=true

# IO Scheduler
default_io_sched=maple

# SUFS
susfs_enabled=true
EOF

chown system:system /data/adb/infinity_kernel/default.conf 2>/dev/null
ui_print "  [OK] Default config created"

# ---- Create Custom Task Profiles Config (user-editable) ----
if [ ! -f "/data/adb/infinity_kernel/task_profiles.conf" ]; then
    cat > /data/adb/infinity_kernel/task_profiles.conf << 'EOF'
# Infinity Kernel — Custom Task Profile Overrides
# Add your own app -> profile mappings here
# Format: package.name=profile_number
#
# Profile numbers:
#   0=IDLE  1=SOCIAL  2=BROWSE  3=MEDIA  4=NORMAL
#   5=IO_HEAVY  6=GAMING_LIGHT  7=GAMING_HEAVY  8=CHARGING
#
# Examples (uncomment to use):
# com.your.game=7
# com.your.app=1
#
# To find a package name: dumpsys window | grep mCurrentFocus
EOF
    chown system:system /data/adb/infinity_kernel/task_profiles.conf 2>/dev/null
    ui_print "  [OK] Task profiles config created"
fi

ui_print " "

##########################################################################################
# COMPLETE
##########################################################################################

ui_print "  ╔═══════════════════════════════════════════╗"
ui_print "  ║   INFINITY KERNEL v2.0 INSTALLED!       ║"
ui_print "  ╚═══════════════════════════════════════════╝"
ui_print " "
ui_print "  Auto Performance Profiles:"
ui_print "    IDLE / SOCIAL / BROWSE / MEDIA / NORMAL"
ui_print "    IO_HEAVY / GAMING_LIGHT / GAMING_HEAVY"
ui_print "    CHARGING (cool charge mode)"
ui_print " "
ui_print "  Task Engine SysFS:"
ui_print "    /sys/kernel/infinity_task_engine/"
ui_print "    - current_profile   (read current)"
ui_print "    - force_profile     (0=auto, 1-8=force)"
ui_print "    - auto_detect       (0/1)"
ui_print "    - stats             (show stats)"
ui_print " "
ui_print "  Charging SysFS:"
ui_print "    /sys/.../infinity_charging/"
ui_print "    - bypass_enable     (0/1)"
ui_print "    - gaming_mode       (0-3)"
ui_print "    - charge_current    (100-5000 mA)"
ui_print " "
ui_print "  Multi-Stage Thermal:"
ui_print "    38C -> reduce 30% | 42C -> reduce 60%"
ui_print "    45C -> pause charge | 39C -> resume"
ui_print " "
ui_print "  Root: $ROOT_DETECTED"
ui_print "  RAM: 8GB | ZRAM: 5GB LZ4 | TCP: BBRv2"
ui_print " "
ui_print "  Edit /data/adb/infinity_kernel/task_profiles.conf"
ui_print "  to add custom app -> profile mappings!"
ui_print " "
ui_print "  Reboot to apply all changes!"
ui_print " "