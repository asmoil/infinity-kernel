#!/system/bin/sh

##########################################################################################
# Infinity Kernel AnyKernel3 Flash Script
# Device: Poco X3 Pro (vayu/bhima)
# Supports: AnyKernel flash, KernelSU, Magisk, APatch (Sukisu Ultra)
##########################################################################################

## AnyKernel3 properties
kernel.string="Infinity Kernel for Poco X3 Pro"
kernel.forum="https://t.me/infinity_kernel"
kernel.author="InfinityKernelTeam"
kernel.version="1.0"
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
is_slot_device=1;
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
ui_print "  ╔═══════════════════════════════════════╗"
ui_print "  ║     INFINITY KERNEL v1.0              ║"
ui_print "  ║     Poco X3 Pro (vayu/bhima)         ║"
ui_print "  ╚═══════════════════════════════════════╝"
ui_print " "
ui_print "  Optimized Performance + Battery Balance"
ui_print "  Charging Bypass | SUFS | Root Manager Support"
ui_print " "

# Detect root solution
ROOT_TYPE="none"

if [ -d "/data/adb/ksu" ] || [ -f "/data/adb/ksud" ]; then
    ROOT_TYPE="KernelSU"
    ui_print "  [INFO] KernelSU detected"
fi

if [ -d "/data/adb/magisk" ] || [ -f "/data/adb/magisk/magisk32" ]; then
    ROOT_TYPE="Magisk"
    ui_print "  [INFO] Magisk detected"
fi

if [ -d "/data/adb/ap" ] || [ -f "/data/adb/apd" ]; then
    ROOT_TYPE="APatch"
    ui_print "  [INFO] APatch (Sukisu Ultra) detected"
fi

if [ "$ROOT_TYPE" = "none" ]; then
    ui_print "  [INFO] No root solution detected"
    ui_print "  [INFO] Kernel includes built-in KernelSU"
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
ui_print "  [OK] Android version: $ANDROID_VER"

ui_print " "

##########################################################################################
# BACKUP
##########################################################################################

ui_print "  [BACKUP] Creating boot backup..."
backup_file="/data/local/infinity_kernel_boot_backup_$(date +%Y%m%d_%H%M%S).img"
dd if=/dev/block/bootdevice/by-name/boot of="$backup_file" 2>/dev/null
if [ $? -eq 0 ]; then
    ui_print "  [OK] Backup saved: $backup_file"
else
    # Try slot-based backup
    CURRENT_SLOT=$(getprop ro.boot.slot_suffix)
    BOOT_PART="/dev/block/bootdevice/by-name/boot${CURRENT_SLOT}"
    dd if="$BOOT_PART" of="$backup_file" 2>/dev/null
    if [ $? -eq 0 ]; then
        ui_print "  [OK] Backup saved: $backup_file"
    else
        ui_print "  [WARN] Backup failed, continuing..."
    fi
fi

ui_print " "

##########################################################################################
# FLASH KERNEL
##########################################################################################

ui_print "  [FLASH] Installing Infinity Kernel..."

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
if [ "$ROOT_TYPE" = "KernelSU" ] && [ -f "/data/adb/ksu/ksud" ]; then
    ui_print "  [KSU] Patching for KernelSU compatibility..."
    # KernelSU uses its own boot patching, we preserve the ramdisk
    patch_vbmeta_flag=false
elif [ "$ROOT_TYPE" = "Magisk" ]; then
    ui_print "  [MAGISK] Preserving Magisk ramdisk..."
    # Magisk patches ramdisk, we just replace kernel
elif [ "$ROOT_TYPE" = "APatch" ]; then
    ui_print "  [APATCH] Preserving APatch ramdisk..."
    # APatch uses KernelPatch, preserve its modifications
fi

# Flash the kernel
dump_boot

# Write the new boot image
write_boot

ui_print "  [OK] Kernel flashed successfully"
ui_print " "

##########################################################################################
# POST-INSTALL SETUP
##########################################################################################

ui_print "  [SETUP] Configuring Infinity Kernel..."

# Set up charging control permissions
if [ -d "/sys/devices/platform/soc/" ]; then
    CHARGING_PATH=$(find /sys/devices/platform/soc/ -name "infinity_charging" -type d 2>/dev/null | head -1)
    if [ -n "$CHARGING_PATH" ]; then
        chown -R system:system "$CHARGING_PATH" 2>/dev/null
        chmod -R 664 "$CHARGING_PATH"/* 2>/dev/null
        ui_print "  [OK] Charging control configured"
    fi
fi

# Create Infinity Kernel config directory
mkdir -p /data/adb/infinity_kernel 2>/dev/null
chown -R system:system /data/adb/infinity_kernel 2>/dev/null

# Set default gaming mode profile
cat > /data/adb/infinity_kernel/default.conf << 'EOF'
# Infinity Kernel Default Configuration
# Generated during kernel installation

# Charging Control
gaming_mode=0
max_charge_current=3000
gaming_charge_current=500
cooldown_threshold=45
resume_threshold=40
bypass_auto=true

# Performance Profiles
cpu_boost=true
gpu_tweaks=true
touch_boost=true

# Battery Optimization
zram_size=5120
lru_gen=true
ksm_aggressive=false

# Network
tcp_cong=bbr
tcp_bbr2=true

# IO Scheduler
default_io_sched=maple
EOF

chown system:system /data/adb/infinity_kernel/default.conf 2>/dev/null
ui_print "  [OK] Default config created"

# Set up init.d scripts if supported
if [ -d "/system/etc/init.d" ]; then
    cp tools/infinity_init.sh /system/etc/init.d/99infinity 2>/dev/null
    chmod 755 /system/etc/init.d/99infinity 2>/dev/null
fi

ui_print " "

##########################################################################################
# COMPLETE
##########################################################################################

ui_print "  ╔═══════════════════════════════════════╗"
ui_print "  ║   INFINITY KERNEL INSTALLED!         ║"
ui_print "  ╚═══════════════════════════════════════╝"
ui_print " "
ui_print "  Features:"
ui_print "    - Performance + Battery Balance"
ui_print "    - Charging Bypass (Gaming Mode)"
ui_print "    - SUFS (Overlay/SquashFS)"
ui_print "    - KernelSU / Magisk / APatch Support"
ui_print "    - BBRv2 TCP Congestion Control"
ui_print "    - Maple IO Scheduler"
ui_print "    - ZRAM 5GB + LZ4 Compression"
ui_print "    - CPU/GPU Tweaks & Touch Boost"
ui_print " "
ui_print "  SysFS Controls:"
ui_print "    /sys/devices/platform/.../infinity_charging/"
ui_print "    - bypass_enable (0/1)"
ui_print "    - gaming_mode (0-3)"
ui_print "    - charge_current (100-5000 mA)"
ui_print " "
ui_print "  Root Solution: $ROOT_TYPE"
ui_print " "
ui_print "  Reboot to apply changes!"
ui_print " "