#!/bin/sh
# Infinity Kernel Flasher - AnyKernel3
# SPDX-License-Identifier: GPL-2.0-only

## AnyKernel3 Header
OUTFD=/proc/self/fd/$2

#############################################
# UI helpers
#############################################
ui_print() {
    echo "ui_print $1" > "$OUTFD"
    echo "ui_print" > "$OUTFD"
}

abort() {
    ui_print "ERROR: $1"
    echo "ui_print" > "$OUTFD"
    exit 1
}

file_getprop() {
    grep "^$2=" "$1" | head -n1 | cut -d= -f2-
}

#############################################
# A/B Slot Detection (10 methods)
#############################################
detect_slot() {
    SLOT=""
    # Method 1: getprop
    if [ -n "$(getprop ro.boot.slot_suffix 2>/dev/null)" ]; then
        SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null)
    # Method 2: ro.boot.slot
    elif [ -n "$(getprop ro.boot.slot 2>/dev/null)" ]; then
        SLOT="_$(getprop ro.boot.slot 2>/dev/null)"
    # Method 3: kernel cmdline
    elif [ -f /proc/cmdline ]; then
        local cmdline_slot=$(cat /proc/cmdline | tr ' ' '\n' | grep "androidboot.slot_suffix=" | head -1 | cut -d= -f2)
        [ -n "$cmdline_slot" ] && SLOT="$cmdline_slot"
    fi
    if [ -z "$SLOT" ]; then
        # Method 4: readlink /dev/block/by-name/boot
        if [ -L /dev/block/by-name/boot ]; then
            local target=$(readlink /dev/block/by-name/boot)
            case "$target" in
                *boot_a*) SLOT="_a" ;;
                *boot_b*) SLOT="_b" ;;
            esac
        fi
    fi
    if [ -z "$SLOT" ]; then
        # Method 5: check boot_a existence and compare with active
        if [ -e /dev/block/by-name/boot_a ]; then
            # Method 6: compare active slot from /proc/cmdline
            local active=$(cat /proc/cmdline 2>/dev/null | tr ' ' '\n' | grep "androidboot.slot" | head -1 | cut -d= -f2)
            if [ "$active" = "a" ]; then
                SLOT="_a"
            elif [ "$active" = "b" ]; then
                SLOT="_b"
            elif [ -e /dev/block/by-name/boot_b ]; then
                # Method 7: neither known, default to _a
                SLOT="_a"
            fi
        fi
    fi
    if [ -z "$SLOT" ]; then
        # Method 8: check /system/etc/build.prop
        if [ -f /system/etc/build.prop ]; then
            local ab=$(file_getprop /system/etc/build.prop ro.build.ab_update)
            [ "$ab" = "true" ] && SLOT="_a"
        fi
    fi
    if [ -z "$SLOT" ]; then
        # Method 9: fstab check for /boot
        if [ -f /etc/fstab.qcom ]; then
            local fstab_boot=$(grep '/boot ' /etc/fstab.qcom 2>/dev/null | head -1)
            case "$fstab_boot" in
                *boot_a*) SLOT="_a" ;;
                *boot_b*) SLOT="_b" ;;
            esac
        fi
    fi
    if [ -z "$SLOT" ]; then
        # Method 10: device tree compatible check + fallback
        if [ -e /dev/block/by-name/boot ]; then
            SLOT=""
            ui_print "  No A/B slot detected, using non-slotted boot"
        else
            abort "Cannot determine boot partition"
        fi
    fi
    ui_print "  Detected slot: ${SLOT:-none (A-only)}"
}

#############################################
# Find block device
#############################################
find_block() {
    local name="$1"
    local block=""
    # Try by-name first
    if [ -e "/dev/block/by-name/$name" ]; then
        block="/dev/block/by-name/$name"
    elif [ -e "/dev/block/platform/*/by-name/$name" ]; then
        block=$(find /dev/block/platform -name "$name" -type l 2>/dev/null | head -1)
    elif [ -e "/dev/block/bootdevice/by-name/$name" ]; then
        block="/dev/block/bootdevice/by-name/$name"
    fi
    echo "$block"
}

#############################################
# Magic bytes check
#############################################
check_magic() {
    local file="$1"
    local magic
    magic=$(dd if="$file" bs=8 count=1 2>/dev/null | od -A n -t x1 | tr -d ' ')
    case "$magic" in
        414e44524f494421*|ANDROID!*) return 0 ;;
        *) return 1 ;;
    esac
}

#############################################
# Main
#############################################
ui_print ""
ui_print "  Infinity Kernel Flasher"
ui_print ""

# Detect A/B slot
detect_slot

# Find boot block
block=$(find_block "boot${SLOT}")
[ -z "$block" ] && abort "Boot partition not found"
ui_print "  Boot device: $block"

# ===========================================
# Step 1: Dump boot image, verify, truncate
# ===========================================
ui_print "  [1/5] Dumping boot image..."
dd if="$block" of=/tmp/boot.img bs=4096 2>/dev/null
[ ! -f /tmp/boot.img ] && abort "Failed to dump boot image"

# Verify ANDROID! magic
if ! check_magic /tmp/boot.img; then
    abort "Boot image does not have ANDROID! magic"
fi
ui_print "  ANDROID! magic verified"

# Read boot header fields
page_size=$(dd if=/tmp/boot.img bs=1 skip=36 count=4 2>/dev/null | od -A n -t d4 | tr -d ' ')
kernel_size=$(dd if=/tmp/boot.img bs=1 skip=8 count=4 2>/dev/null | od -A n -t d4 | tr -d ' ')
ramdisk_size=$(dd if=/tmp/boot.img bs=1 skip=16 count=4 2>/dev/null | od -A n -t d4 | tr -d ' ')
second_size=$(dd if=/tmp/boot.img bs=1 skip=12 count=4 2>/dev/null | od -A n -t d4 | tr -d ' ')
header_version=$(dd if=/tmp/boot.img bs=1 skip=40 count=4 2>/dev/null | od -A n -t d4 | tr -d ' ')

ui_print "  page_size=$page_size kernel_size=$kernel_size ramdisk_size=$ramdisk_size"
ui_print "  second_size=$second_size header_version=$header_version"

# Calculate actual image size
header_size=$((page_size))
actual_size=$((header_size))
# Align to page_size
actual_size=$(( (kernel_size + page_size - 1) / page_size * page_size ))
actual_size=$((actual_size + (ramdisk_size + page_size - 1) / page_size * page_size ))
if [ "$second_size" -gt 0 ]; then
    actual_size=$((actual_size + (second_size + page_size - 1) / page_size * page_size))
fi
# Add recovery dtbo for header v1+v2
if [ "$header_version" -ge 1 ]; then
    actual_size=$((actual_size + page_size))
fi
# Add dtb for header v2
if [ "$header_version" -ge 2 ]; then
    actual_size=$((actual_size + page_size))
fi

# Truncate to actual size to remove extra padding/junk
if [ -f /tmp/boot.img ]; then
    truncate -s "$actual_size" /tmp/boot.img
    ui_print "  Boot image truncated to $actual_size bytes"
fi

# ===========================================
# Step 2: Unpack with magiskboot
# ===========================================
ui_print "  [2/5] Unpacking boot image..."

MAGISKBOOT=""
if [ -x "${PWD}/tools/anykernel3/magiskboot" ]; then
    MAGISKBOOT="${PWD}/tools/anykernel3/magiskboot"
elif command -v magiskboot >/dev/null 2>&1; then
    MAGISKBOOT="magiskboot"
elif [ -x "/data/adb/magisk/magiskboot" ]; then
    MAGISKBOOT="/data/adb/magisk/magiskboot"
else
    abort "magiskboot not found (bundled or system)"
fi

ui_print "  Using magiskboot: $MAGISKBOOT"
cd /tmp
$MAGISKBOOT unpack boot.img 2>&1 | while IFS= read -r line; do
    ui_print "    $line"
done

ui_print "  Extracted files:"
for f in kernel ramdisk.cpio dtb kernel_dtb extra; do
    if [ -f "/tmp/$f" ]; then
        sz=$(stat -c%s "/tmp/$f" 2>/dev/null || echo "0")
        ui_print "    $f ($sz bytes)"
    fi
done

# ===========================================
# Step 3: Replace kernel
# ===========================================
ui_print "  [3/5] Replacing kernel..."
if [ ! -f "${PWD}/Image.gz" ]; then
    abort "Image.gz not found in flasher directory"
fi
cp "${PWD}/Image.gz" /tmp/kernel
ui_print "  Kernel replaced"

# ===========================================
# Step 4: Repack boot image
# ===========================================
ui_print "  [4/5] Repacking boot image..."
$MAGISKBOOT repack boot.img new-boot.img 2>&1 | while IFS= read -r line; do
    ui_print "    $line"
done

[ ! -f /tmp/new-boot.img ] && abort "Repack failed"

# Verify new image has ANDROID! magic
if ! check_magic /tmp/new-boot.img; then
    abort "Repacked image missing ANDROID! magic"
fi
ui_print "  New boot image verified (${header_version})"

# ===========================================
# Step 5: Flash boot image
# ===========================================
ui_print "  [5/5] Flashing boot image..."
dd if=/tmp/new-boot.img of="$block" bs=4096 2>/dev/null
if [ $? -ne 0 ]; then
    abort "Failed to flash boot image"
fi

# Verify flash by reading back 8 bytes
verify=$(dd if="$block" bs=8 count=1 2>/dev/null | od -A n -t x1 | tr -d ' ')
case "$verify" in
    414e44524f494421*|ANDROID!*) ui_print "  Flash verified" ;;
    *) abort "Flash verification failed (magic mismatch)" ;;
esac

# ===========================================
# DTBO flash
# ===========================================
if [ -f "${PWD}/dtbo.img" ]; then
    ui_print "  Flashing DTBO..."
    dtbo_block=$(find_block "dtbo${SLOT}")
    if [ -n "$dtbo_block" ] && [ -e "$dtbo_block" ]; then
        dd if="${PWD}/dtbo.img" of="$dtbo_block" bs=4096 2>/dev/null
        ui_print "  DTBO flashed to $dtbo_block"
    else
        ui_print "  DTBO partition not found, skipping"
    fi
fi

# ===========================================
# Cleanup
# ===========================================
cd /
rm -rf /tmp/boot.img /tmp/new-boot.img /tmp/kernel /tmp/ramdisk.cpio /tmp/dtb /tmp/kernel_dtb 2>/dev/null

ui_print ""
ui_print "  ========================================"
ui_print "  Infinity Kernel flashed successfully!"
ui_print "  ========================================"
ui_print ""

# AnyKernel3 properties function
properties() {
    :
}

kernel_string="Infinity Kernel v4.0.0"
kernel_file="Image.gz"
device_name1="vayu"
device_name2="bhima"
