#!/bin/sh
# *******************************************************************************
# Infinity Kernel - AnyKernel3 Flash Script
# Device: Poco X3 Pro (vayu/bhima)
# SoC: SM8250-AC (Snapdragon 860)
# *******************************************************************************

## AnyKernel3 variables
is_slot_device=0
do.systemless=1
kernel_strings="Infinity Kernel"
device_names="vayu,bhima"

## AnyKernel3 functions
ui_print() {
    echo "ui_print $1" > /proc/self/fd/$OUTFD
    echo "ui_print" > /proc/self/fd/$OUTFD
}

grep_prop() {
    local regex=$1 prop_file=$2
    if [ -f "$prop_file" ]; then
        local line=$(sed -n "s/^$regex=//p" "$prop_file" 2>/dev/null)
        echo "$line"
    fi
}

abort() {
    ui_print "ERROR: $1"
    ui_print " "
    exit 1
}

## Detect boot partition
find_boot_partition() {
    if [ -d /dev/block/by-name ]; then
        BOOTIMAGE=/dev/block/by-name/boot
    elif [ -d /dev/block/platform ]; then
        BOOTIMAGE=$(find /dev/block/platform -type l -name boot 2>/dev/null | head -n1)
    fi
    if [ -z "$BOOTIMAGE" ] || [ ! -e "$BOOTIMAGE" ]; then
        abort "Cannot find boot partition!"
    fi
}

## Device check
device_check() {
    local found=0
    local dev_name=$(getprop ro.product.device)
    local hw_name=$(getprop ro.hardware)
    local model=$(getprop ro.product.model)

    for d in $(echo "$device_names" | tr ',' ' '); do
        if [ "$dev_name" = "$d" ] || [ "$hw_name" = "$d" ]; then
            found=1
            break
        fi
    done

    if [ $found -eq 0 ]; then
        ui_print " "
        ui_print "⚠  Unsupported device detected!"
        ui_print "   Device: $dev_name ($hw_name)"
        ui_print "   Model:  $model"
        ui_print "   This kernel is ONLY for: $device_names"
        ui_print " "
        abort "Flashing aborted - wrong device"
    fi
}

## ROM detection
rom_detect() {
    rom="Unknown"
    local bp=/system/build.prop
    if [ -f $bp ]; then
        if grep -q "ro.miui.ui.version.name" $bp; then
            rom="MIUI"
        elif grep -q "ro.lineage.version" $bp; then
            rom="LineageOS"
        elif grep -q "ro.crdroid.version" $bp; then
            rom="crDroid"
        elif grep -q "ro.xtended.version" $bp; then
            rom="Xtended"
        elif grep -q "ro.pa.flavor" $bp || grep -q "ro.paranoid.version" $bp; then
            rom="Paranoid Android"
        elif grep -q "ro.aoscp.version" $bp; then
            rom="AOSCP"
        elif grep -q "ro.havoc.version" $bp; then
            rom="Havoc-OS"
        elif grep -q "ro.evolution.version" $bp; then
            rom="Evolution X"
        else
            rom="AOSP"
        fi
    else
        rom="Unknown"
    fi
}

## Root manager detection
detect_root() {
    root_mgr="None"

    # KernelSU (original)
    if [ -d /data/adb/ksu ]; then
        if [ -f /data/adb/ksu/ksud ] || [ -f /data/adb/ksu/bin/ksud ]; then
            root_mgr="KernelSU"
        fi
    fi

    # KernelSU-Next (KSU)
    if [ "$root_mgr" = "None" ] && [ -d /data/adb/kernel ]; then
        if [ -f /data/adb/kernel/ksud ] || [ -f /data/adb/kernel/bin/ksud ]; then
            root_mgr="KSU (KernelSU-Next)"
        fi
    fi

    # APatch
    if [ "$root_mgr" = "None" ] && [ -d /data/adb/ap ]; then
        root_mgr="APatch"
    fi

    # Magisk
    if [ "$root_mgr" = "None" ]; then
        if [ -f /data/adb/magisk/magisk32 ] || [ -f /data/adb/magisk/magisk64 ] || [ -f /data/adb/magisk/magisk ]; then
            root_mgr="Magisk"
        fi
    fi
}

## Kyriepatch - only for MIUI
apply_kyriepatch() {
    if [ "$rom" = "MIUI" ]; then
        if [ -f $tools/kyriepatch.sh ]; then
            ui_print " "
            ui_print ">>> Applying Kyriepatch for MIUI..."
            bash $tools/kyriepatch.sh
            ui_print ">>> Kyriepatch applied."
        else
            ui_print " "
            ui_print ">>> Kyriepatch script not found, skipping."
        fi
    fi
}

## Backup current kernel
backup_kernel() {
    ui_print " "
    ui_print "- Backing up current kernel..."
    if [ -e "$BOOTIMAGE" ]; then
        dd if=$BOOTIMAGE of=${BOOTIMAGE}.bak 2>/dev/null
        if [ $? -eq 0 ]; then
            ui_print "  Backup saved to ${BOOTIMAGE}.bak"
        else
            ui_print "  Warning: Backup failed (may be non-critical)."
        fi
    fi
}

## Flash kernel via dd
flash_kernel() {
    ui_print " "
    ui_print "- Flashing Infinity Kernel..."
    if [ ! -f $kernel ]; then
        abort "Kernel image not found: $kernel"
    fi
    dd if=$kernel of=$BOOTIMAGE bs=4096 2>/dev/null
    if [ $? -ne 0 ]; then
        abort "Kernel flash failed!"
    fi
    ui_print "  Kernel flashed successfully."
}

## Install init script to run on boot
install_init_script() {
    ui_print " "
    ui_print "- Installing boot init script..."
    if [ -f $tools/infinity_init.sh ]; then
        local target_dir=/data/adb/service.d
        mkdir -p $target_dir
        cp $tools/infinity_init.sh $target_dir/infinity_init.sh
        chmod 0755 $target_dir/infinity_init.sh
        chcon u:object_r:system_file:s0 $target_dir/infinity_init.sh
        ui_print "  Installed to $target_dir/infinity_init.sh"
    else
        ui_print "  Warning: infinity_init.sh not found."
    fi
}

## Display device info
show_info() {
    ui_print " "
    ui_print "══════════════════════════════════════"
    ui_print "  Infinity Kernel"
    ui_print "  Poco X3 Pro (vayu/bhima)"
    ui_print "══════════════════════════════════════"
    ui_print " "
    ui_print "  Device  : $(getprop ro.product.device)"
    ui_print "  Model   : $(getprop ro.product.model)"
    ui_print "  Android : $(getprop ro.build.version.release)"
    ui_print "  ROM     : $rom"
    ui_print "  Root    : $root_mgr"
    ui_print " "
}

## Main
OUTFD=$2
ZIPFILE=$3

cd /dev/tmp
tools=/dev/tmp/tools
kernel=/dev/tmp/Image.gz-dtb

# Begin
ui_print " "
ui_print "  ╔══════════════════════════════════╗"
ui_print "  ║     Infinity Kernel Flasher      ║"
ui_print "  ║     AnyKernel3 Edition           ║"
ui_print "  ╚══════════════════════════════════╝"
ui_print " "

# Ensure /system is mounted
mount /system 2>/dev/null
mount -o remount,rw /system 2>/dev/null

# Device check
device_check

# Detect ROM and root
rom_detect
detect_root

# Find boot partition
find_boot_partition

# Show info banner
show_info

# Backup
backup_kernel

# Flash kernel
flash_kernel

# Install boot init script
install_init_script

# Kyriepatch (MIUI only)
apply_kyriepatch

# Done
ui_print " "
ui_print "✓  Infinity Kernel installed successfully!"
ui_print "  Please reboot to apply changes."
ui_print " "

exit 0