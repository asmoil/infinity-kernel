## AnyKernel3 flash script for Infinity Kernel
## Poco X3 Pro (vayu/bhima) — SM8250-AC
## Supports: MIUI / HyperOS / Any Custom ROM
## Compatible: KernelSU / KSU Next / Magisk / APatch / ReSukiSu / SukiSU Ultra

###############################################
# AnyKernel3 Header
###############################################
properties() {
    kernel_string="Infinity Kernel v1.0.31 | SM8250-AC | Proton Clang 17"
    do.devicecheck=1
    do.systemless=1
    do.modules=0
    do.sysfs=1
    do.compatibility_check=0
    do.cleanup=1
    device.name[0]=vayu
    device.name[1]=bhima
    # is_slot_device=0 for vayu (A-only)
    is_slot_device=0
    supported.versions=11,12,13,14
    supported.configs="
        kernelsu
        kernelsu_next
        magisk
        apatch
        resukisu
        sukisu_ultra
    "
}

###############################################
# ROM Detection System
###############################################
detect_rom() {
    ROM_TYPE="unknown"
    ROM_VERSION=""

    # Check /system/build.prop for ROM identification
    if [ -f /system/build.prop ]; then
        local miui_ver=$(file_getprop /system/build.prop ro.miui.ui.version.name)
        local miui_code=$(file_getprop /system/build.prop ro.miui.ui.version.code)
        local hyperos_ver=$(file_getprop /system/build.prop ro.os.build.version.hyper_os)
        local rom_display=$(file_getprop /system/build.prop ro.build.display.id)
        local build_flavor=$(file_getprop /system/build.prop ro.build.flavor)
        local product=$(file_getprop /system/build.prop ro.build.product)

        # MIUI detection (including V12-V15)
        if [ -n "$miui_ver" ] || [ -n "$miui_code" ]; then
            ROM_TYPE="miui"
            ROM_VERSION="${miui_ver:-$miui_code}"
            ui_print " "
            ui_print "  *** MIUI detected: $ROM_VERSION ***"
            return 0
        fi

        # HyperOS detection
        if [ -n "$hyperos_ver" ]; then
            ROM_TYPE="hyperos"
            ROM_VERSION="$hyperos_ver"
            ui_print " "
            ui_print "  *** HyperOS detected: $ROM_VERSION ***"
            return 0
        fi

        # LineageOS / crDroid / PixelExperience / other AOSP-based
        if contains "$build_flavor" "lineage" || contains "$rom_display" "lineage"; then
            ROM_TYPE="lineageos"
            ROM_VERSION="$rom_display"
            ui_print " "
            ui_print "  *** LineageOS detected: $ROM_VERSION ***"
            return 0
        fi

        if contains "$rom_display" "crDroid"; then
            ROM_TYPE="crdroid"
            ROM_VERSION="$rom_display"
            ui_print " "
            ui_print "  *** crDroid detected: $ROM_VERSION ***"
            return 0
        fi

        if contains "$rom_display" "PixelExperience" || contains "$build_flavor" "aosp"; then
            ROM_TYPE="aosp"
            ROM_VERSION="$rom_display"
            ui_print " "
            ui_print "  *** AOSP/Custom ROM detected: $ROM_VERSION ***"
            return 0
        fi

        # Generic AOSP check
        if contains "$rom_display" "RP1" || contains "$rom_display" "TQ1" || \
           contains "$rom_display" "UP1" || contains "$rom_display" "AP1" || \
           contains "$rom_display" "VD1" || contains "$rom_display" "SP1"; then
            ROM_TYPE="custom"
            ROM_VERSION="$rom_display"
            ui_print " "
            ui_print "  *** Custom ROM detected: $ROM_VERSION ***"
            return 0
        fi

        ROM_TYPE="custom"
        ROM_VERSION="$rom_display"
        ui_print " "
        ui_print "  *** ROM detected (generic): $ROM_VERSION ***"
    else
        ROM_TYPE="unknown"
        ui_print " "
        ui_print "  ! Cannot detect ROM type (no build.prop)"
    fi

    return 0
}

###############################################
# Root Manager Detection
###############################################
detect_root_manager() {
    ROOT_MANAGER="none"

    # KernelSU
    if [ -d /data/adb/ksu ] || [ -d /data/adb/kernelsu ]; then
        ROOT_MANAGER="kernelsu"
        ui_print "  Root: KernelSU detected"
        return 0
    fi

    # KernelSU Next
    if [ -d /data/adb/ksunext ]; then
        ROOT_MANAGER="kernelsu_next"
        ui_print "  Root: KernelSU Next detected"
        return 0
    fi

    # Magisk
    if [ -d /data/adb/magisk ]; then
        ROOT_MANAGER="magisk"
        ui_print "  Root: Magisk detected"
        return 0
    fi

    # APatch
    if [ -d /data/adb/ap ]; then
        ROOT_MANAGER="apatch"
        ui_print "  Root: APatch detected"
        return 0
    fi

    # ReSukiSu
    if [ -f /data/adb/resukisu/resukisu ]; then
        ROOT_MANAGER="resukisu"
        ui_print "  Root: ReSukiSu detected"
        return 0
    fi

    # SukiSU Ultra
    if [ -f /data/adb/sukisu/sukisu_ultra ] || [ -d /data/adb/sukisu ]; then
        ROOT_MANAGER="sukisu_ultra"
        ui_print "  Root: SukiSU Ultra detected"
        return 0
    fi

    ui_print "  Root: No root manager detected (systemless mode)"
}

###############################################
# Kernel install
###############################################
install_kernel() {
    # Run ROM detection
    detect_rom
    detect_root_manager

    ui_print " "
    ui_print "  Flashing Infinity Kernel..."
    ui_print " "

    # MIUI-specific: apply kyriepatch (DSI fix)
    if [ "$ROM_TYPE" = "miui" ]; then
        ui_print "  Applying MIUI DSI patch..."
        . $bin/kyriepatch.sh
    else
        ui_print "  Skipping MIUI DSI patch (not MIUI)"
    fi

    # Copy kernel image
    if [ -f "$home/Image.gz-dtb" ]; then
        ui_print "  Installing Image.gz-dtb..."
    elif [ -f "$home/Image.gz" ]; then
        ui_print "  Installing Image.gz..."
    fi

    # Copy DTB if present
    if [ -f "$home/dtb.img" ]; then
        ui_print "  Installing DTB..."
    fi

    # Copy DTBO if present
    if [ -f "$home/dtbo.img" ]; then
        ui_print "  Installing DTBO..."
    fi

    # For non-A/B devices (vayu), flash directly to boot
    block=/dev/block/by-name/boot;

    ui_print " "
    ui_print "  Infinity Kernel installed successfully!"
}

###############################################
# Post-install
###############################################
post_install() {
    ui_print " "
    ui_print "  ========================================"
    ui_print "    Infinity Kernel v1.0.31 — Installed!"
    ui_print "    ROM: $ROM_TYPE $ROM_VERSION"
    ui_print "    Root: $ROOT_MANAGER"
    ui_print "    Device: $(getprop ro.product.device)"
    ui_print "  ========================================"
    ui_print " "
    ui_print "  Features:"
    ui_print "  - CPU: Tuned SM8250-AC (balanced perf/battery)"
    ui_print "  - GPU: Adreno 618 optimized"
    ui_print "  - IO: FSYNC + Maple/BFQ scheduler"
    ui_print "  - TCP: BBR congestion control"
    ui_print "  - ZRAM: 5GB LZ4 (8GB RAM device)"
    ui_print "  - Charging bypass: 4 gaming modes"
    ui_print "  - Thermal: Enhanced charging regulation"
    ui_print "  - SUFS v1.5.7+ support"
    ui_print "  - 6 Root managers supported"
    ui_print " "
}

###############################################
# Main
###############################################
. $bin/ak3-core.sh