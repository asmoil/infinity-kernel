# AnyKernel3 Flash Script
# Infinity Kernel for Poco X3 Pro (vayu/bhima) | SM8150

## AnyKernel3 parameters
kernel.string="Infinity Kernel"
device.name1=vayu
device.name2=bhima
supported.versions=11,12,13,14,15,16
supported.patchlevels=

## Flashing options
do.devicecheck=1
do.systemless=1
do.cleanflash=0
do.promptforclean=0

## Shell variables
block=/dev/block/bootdevice/by-name/boot
is_slot_device=1
slot_select=1

## Functions

# Dump boot partition and extract contents
dump_boot() {
  dd if="$1" of="$2" bs=4096 2>/dev/null
}

# Write image to boot partition
flash_boot() {
  dd if="$1" of="$2" bs=4096 2>/dev/null
}

# Backup current boot image
backup_boot() {
  if [ "$do.backcup" != "0" ]; then
    local bak="${BACKUP_DIR:-/sdcard}/InfinityKernel-backup${SLOT}.img"
    ui_print "  Backing up current boot image..."
    dd if="${block}${SLOT}" of="$bak" bs=4096 2>/dev/null
    ui_print "  Backup saved to: $bak"
  fi
}

# Check device compatibility
check_device() {
  local prop
  prop=$(getprop ro.product.device 2>/dev/null)
  case "$prop" in
    vayu|bhima) return 0 ;;
  esac
  prop=$(getprop ro.product.model 2>/dev/null)
  case "$prop" in
    *M2102J20SG*|*M2102K20G*) return 0 ;;
  esac
  return 1
}

# Verify boot partition exists
check_boot() {
  [ -b "${block}${SLOT}" ] || [ -e "${block}${SLOT}" ]
}

## Main installation

ui_print " "
ui_print "  Device check..."
if [ "$do.devicecheck" != "0" ]; then
  if ! check_device; then
    ui_print "  WARNING: Device may not be compatible!"
    ui_print "  Expected: vayu / bhima (Poco X3 Pro)"
    ui_print "  Found: $(getprop ro.product.device) / $(getprop ro.product.model)"
    ui_print " "
    ui_print "  Flashing anyway in 3 seconds..."
    sleep 3
  else
    ui_print "  Device verified: $(getprop ro.product.device)"
  fi
fi

ui_print "  Checking boot partition..."
if ! check_boot; then
  abort "Boot partition not found: ${block}${SLOT}"
fi
ui_print "  Boot partition: ${block}${SLOT}"

# Backup
backup_boot

# Remove old Image.gz-dtb if clean flash requested
if [ "$do.cleanflash" != "0" ]; then
  ui_print "  Clean flash requested, removing old Image.gz-dtb..."
  rm -f "$TMPDIR/anykernel/Image.gz-dtb"
fi

# Check that kernel image exists
if [ ! -f "$TMPDIR/anykernel/Image.gz-dtb" ]; then
  abort "Image.gz-dtb not found in ZIP!"
fi

ui_print " "
ui_print "  Flashing kernel..."
flash_boot "$TMPDIR/anykernel/Image.gz-dtb" "${block}${SLOT}"
if [ $? -ne 0 ]; then
  abort "Failed to write boot image!"
fi

# Handle dtb if present
if [ -f "$TMPDIR/anykernel/dtb.img" ]; then
  ui_print "  Flashing DTB..."
  dtb_block=/dev/block/bootdevice/by-name/dtbo
  flash_boot "$TMPDIR/anykernel/dtb.img" "${dtb_block}${SLOT}"
fi

ui_print " "
ui_print "  ═══════════════════════════════════"
ui_print "  Infinity Kernel installed!"
ui_print "  ═══════════════════════════════════"
ui_print " "

## Cleanup
rm -rf "$TMPDIR/anykernel"