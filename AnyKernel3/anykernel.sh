#!/bin/bash
# Infinity Kernel — AnyKernel3 Flash Script
# Device: Poco X3 Pro (vayu/bhima)

## AnyKernel3 usage:
#   install_script=anykernel.sh
#   supported_vendors=Poco,Xiaomi
#   supported_devices=vayu,bhima

## AnyKernel3 permissions:
#   ui_print=true
#   device_check=true

## AnyKernel3 variables:
#   kernel_string=Infinity Kernel
#   kernel_file=Image.gz-dtb
#   dtbo_file=dtbo.img

## AnyKernel3 backup:
#   backup_file=boot.img

ui_print " "
ui_print "╔═══════════════════════════════════════════════════╗"
ui_print "║                                      ║"
ui_print "║   Infinity Kernel — Installer        ║"
ui_print "║   Poco X3 Pro (vayu/bhima)          ║"
ui_print "║                                      ║"
ui_print "╚═══════════════════════════════════════════════════╝"
ui_print " "

# Detect device
if [ ! -f /proc/cmdline ]; then
    ui_print "! /proc/cmdline not found"
    abort "! Cannot detect device"
fi

device=$(grep -oE 'androidboot\.hardware=[^ ]+' /proc/cmdline 2>/dev/null | cut -d= -f2)
board=$(grep -oE 'androidboot\.board=[^ ]+' /proc/cmdline 2>/dev/null | cut -d= -f2)

ui_print "- Device: ${device:-unknown}"
ui_print "- Board: ${board:-unknown}"

case "$device" in
    vayu|bhima)
        ui_print "✓ Device supported!"
        ;;
    *)
        ui_print "! Unsupported device: ${device:-unknown}"
        ui_print "! Only vayu/bhima are supported"
        abort "! This kernel is for Poco X3 Pro only"
        ;;
esac

# Root manager detection
ui_print " "
ui_print "- Root manager compatibility:"
ui_print "  KernelSU-Next / SukiSU-Ultra"
ui_print "  ReSukiSU / KoWSu / APatch"
ui_print "  (universal KSU binary)"

# Flash
ui_print " "
ui_print "- Flashing kernel..."
[ -f "$kernel_file" ] || abort "! $kernel_file not found!"

flash_boot_image "$kernel_file"

if [ -f "$dtbo_file" ]; then
    ui_print "- Flashing dtbo..."
    flash_dtbo_image "$dtbo_file"
fi

ui_print " "
ui_print "╔═══════════════════════════════════════════════════╗"
ui_print "║   Infinity Kernel installed!         ║"
ui_print "║   Reboot to apply changes            ║"
ui_print "╚═══════════════════════════════════════════════════╝"
ui_print " "
