#!/system/bin/sh
# ============================================================================
#  kyriepatch.sh v3.0 – Universal ROM Compatibility for Infinity Kernel
# ============================================================================
#  Supports: MIUI, HyperOS, AOSP, LineageOS, PixelOS, crDroid, Evolution X,
#            Paranoid Android, AOSPExtended, Corvus, Cherish OS, Project Elixir,
#            Spark OS, RisingOS, Nusantara, and ANY custom ROM.
#
#  v3.0 changes:
#    - Added HyperOS detection (OSVERSION/ro.miui.ui.version.name)
#    - Added universal AOSP/custom ROM detection
#    - MIUI DSI patch applied ONLY for MIUI/HyperOS (not AOSP)
#    - fstab patching: ROM-agnostic (handles fstab.qcom, vendor/etc/fstab.qcom,
#      fstab.vayu, fstab.postmarket, etc.)
#    - No-op on unknown ROMs (safe fallback)
# ============================================================================

cmdl_add() {
    local fh=$split_img/header
    local fhmod=$split_img/header.mod
    if ! grep -q "$1" "$fh" 2>/dev/null; then
        cat "$fh" | sed -E "s/cmdline=(.*)/cmdline=\1 $1/" > "$fhmod"
        mv "$fhmod" "$fh"
    fi
}

cmdl_rm() {
    local fh=$split_img/header
    local fhmod=$split_img/header.mod
    if grep -q "$1" "$fh" 2>/dev/null; then
        cat "$fh" | sed -E "s/ $1//" "$fh" > "$fhmod"
        mv "$fhmod" "$fh"
    fi
}

# ============================================================================
# ROM Detection Functions
# ============================================================================

# Returns: "MIUI" | "HYPEROS" | "AOSP" | "CUSTOM" | "UNKNOWN"
detect_rom() {
    local rom="UNKNOWN"

    # -- HyperOS detection --
    # HyperOS sets ro.miui.ui.version.name (e.g. "OS1.0.3.0...")
    # and ro.build.version.os_version for newer builds.
    # Also: ro.xiaomi.device may be set on HyperOS.
    local hyperos_ver="$(getprop ro.miui.ui.version.name 2>/dev/null)"
    local hyperos_tag="$(getprop ro.build.version.hypos 2>/dev/null)"
    local os_version="$(getprop ro.build.version.os_version 2>/dev/null)"

    if [ -n "$hyperos_ver" ] || [ -n "$hyperos_tag" ] || \
       echo "$os_version" | grep -qi "^OS[0-9]"; then
        rom="HYPEROS"
    fi

    # -- MIUI detection --
    if [ "$rom" = "UNKNOWN" ]; then
        local miui_ver="$(getprop ro.miui.ui.version.code 2>/dev/null)"
        local miui_name="$(getprop ro.miui.ui.version.name 2>/dev/null)"
        local build_inc="$(getprop ro.system.build.version.incremental 2>/dev/null)"
        local build_desc="$(getprop ro.build.description 2>/dev/null)"

        # MIUI V12-V14: version.incremental contains "V12.", "V13.", "V14."
        if echo "$build_inc" | grep -q "V1[2-5]\." 2>/dev/null; then
            rom="MIUI"
        # Some MIUI builds expose it via ro.build.description
        elif echo "$build_desc" | grep -qi "MIUI" 2>/dev/null; then
            rom="MIUI"
        # Fallback: miui.ui.version.code exists
        elif [ -n "$miui_ver" ] && [ "$rom" = "UNKNOWN" ]; then
            rom="MIUI"
        fi
    fi

    # -- AOSP-based ROM detection --
    if [ "$rom" = "UNKNOWN" ]; then
        local aosp_flag=0

        # LineageOS
        if getprop ro.lineage.version 2>/dev/null | grep -q .; then
            rom="CUSTOM"
            aosp_flag=1
        fi

        # Pixel Experience / PixelOS
        if [ "$aosp_flag" = "0" ] && getprop ro.pixelexperience.version 2>/dev/null | grep -q .; then
            rom="CUSTOM"
            aosp_flag=1
        fi

        # crDroid
        if [ "$aosp_flag" = "0" ] && getprop ro.cr.version 2>/dev/null | grep -q .; then
            rom="CUSTOM"
            aosp_flag=1
        fi

        # Evolution X
        if [ "$aosp_flag" = "0" ] && getprop ro.evolution.version 2>/dev/null | grep -q .; then
            rom="CUSTOM"
            aosp_flag=1
        fi

        # Paranoid Android
        if [ "$aosp_flag" = "0" ] && getprop ro.pa.version 2>/dev/null | grep -q .; then
            rom="CUSTOM"
            aosp_flag=1
        fi

        # AOSP Extended
        if [ "$aosp_flag" = "0" ] && getprop ro.aex.version 2>/dev/null | grep -q .; then
            rom="CUSTOM"
            aosp_flag=1
        fi

        # Project Elixir
        if [ "$aosp_flag" = "0" ] && getprop ro.elixir.version 2>/dev/null | grep -q .; then
            rom="CUSTOM"
            aosp_flag=1
        fi

        # Corvus
        if [ "$aosp_flag" = "0" ] && getprop ro.corvus.version 2>/dev/null | grep -q .; then
            rom="CUSTOM"
            aosp_flag=1
        fi

        # Cherish OS
        if [ "$aosp_flag" = "0" ] && getprop ro.cherish.version 2>/dev/null | grep -q .; then
            rom="CUSTOM"
            aosp_flag=1
        fi

        # RisingOS
        if [ "$aosp_flag" = "0" ] && getprop ro.rising.version 2>/dev/null | grep -q .; then
            rom="CUSTOM"
            aosp_flag=1
        fi

        # Nusantara
        if [ "$aosp_flag" = "0" ] && getprop ro.nusantara.version 2>/dev/null | grep -q .; then
            rom="CUSTOM"
            aosp_flag=1
        fi

        # Spark OS
        if [ "$aosp_flag" = "0" ] && getprop ro.spark.version 2>/dev/null | grep -q .; then
            rom="CUSTOM"
            aosp_flag=1
        }

        # Generic AOSP detection (fallback)
        if [ "$aosp_flag" = "0" ]; then
            local build_flavor="$(getprop ro.build.flavor 2>/dev/null)"
            local build_tags="$(getprop ro.build.tags 2>/dev/null)"

            # AOSP builds have "test-keys" or specific flavor patterns
            if echo "$build_flavor" | grep -qi "aosp\|lineage\|pixel\|crdroid\|evolution\|paranoid\|elixir\|corvus\|rising\|nusantara\|spark\|cherish" 2>/dev/null; then
                rom="CUSTOM"
            elif echo "$build_tags" | grep -q "test-keys" 2>/dev/null; then
                # test-keys on non-Xiaomi = custom ROM (Xiaomi uses release-keys)
                local vendor="$(getprop ro.product.manufacturer 2>/dev/null)"
                if echo "$vendor" | grep -qi "xiaomi" 2>/dev/null; then
                    # Xiaomi with test-keys might be a custom ROM
                    rom="CUSTOM"
                else
                    rom="AOSP"
                fi
            fi
        fi
    fi

    # -- Final fallback: check for Xiaomi firmware with no MIUI/HyperOS = custom ROM --
    if [ "$rom" = "UNKNOWN" ]; then
        local product="$(getprop ro.product.device 2>/dev/null)"
        case "$product" in
            vayu|bhima)
                # On vayu/bhima without MIUI/HyperOS props = custom ROM
                rom="CUSTOM"
                ;;
        esac
    fi

    echo "$rom"
}

# ============================================================================
# MIUI DSI Patch
# ============================================================================
# ONLY applies to MIUI and HyperOS.
# AOSP/custom ROMs use standard DSI and do NOT need this patch.
# ============================================================================
patch_mi() {
    # Clean up first (in case of re-flash)
    cmdl_rm msm_dsi.phyd_miui=1

    local rom="$1"

    case "$rom" in
        MIUI)
            local vi="$(getprop ro.system.build.version.incremental 2>/dev/null)"
            ui_print "MIUI detected: $vi"
            ui_print "Enabling msm_dsi.phyd_miui for MIUI compatibility..."
            cmdl_add msm_dsi.phyd_miui=1
            ;;
        HYPEROS)
            local hv="$(getprop ro.miui.ui.version.name 2>/dev/null)"
            ui_print "HyperOS detected: $hv"
            ui_print "Enabling msm_dsi.phyd_miui for HyperOS compatibility..."
            cmdl_add msm_dsi.phyd_miui=1
            ;;
        CUSTOM|AOSP)
            ui_print "Custom/AOSP ROM detected: DSI patch NOT needed"
            ui_print "(Standard DSI panel works natively)"
            ;;
        *)
            ui_print "Unknown ROM: DSI patch skipped (safe default)"
            ;;
    esac
}

# ============================================================================
# fstab Universal Patching
# ============================================================================
# Works with any ROM: MIUI, HyperOS, AOSP, custom ROMs.
# Handles different fstab locations and formats.
# ============================================================================
patch_fstab_universal() {
    local rom="$1"

    # Try multiple fstab locations in order of priority
    local fstab_found=0
    local fstab_files="fstab.qcom fstab.vayu fstab.bhima fstab.sm7150 fstab.postmarket"

    for fstab_name in $fstab_files; do
        if [ -f "$ramdisk/etc/$fstab_name" ] || [ -f "$ramdisk/vendor/etc/$fstab_name" ]; then
            local fstab_path=""
            if [ -f "$ramdisk/etc/$fstab_name" ]; then
                fstab_path="$ramdisk/etc/$fstab_name"
            else
                fstab_path="$ramdisk/vendor/etc/$fstab_name"
            fi

            ui_print "fstab found: $fstab_name"

            # Only patch ext4 barrier on MIUI/HyperOS
            # AOSP/custom ROMs typically already have optimized mount options
            case "$rom" in
                MIUI|HYPEROS)
                    # /vendor: barrier=0,nomblk_io_submit (reduces write overhead)
                    if grep -q "/vendor.*ext4.*barrier=1" "$fstab_path" 2>/dev/null; then
                        sed -i 's|/vendor\(.*\)ext4\(.*\)barrier=1|/vendor\1ext4\2barrier=0,nomblk_io_submit|g' "$fstab_path" 2>/dev/null
                    fi
                    # /system: barrier=0
                    if grep -q "/system.*ext4.*barrier=1" "$fstab_path" 2>/dev/null; then
                        sed -i 's|/system\(.*\)ext4\(.*\)barrier=1|/system\1ext4\2barrier=0|g' "$fstab_path" 2>/dev/null
                    fi
                    ui_print "  fstab optimized for $rom"
                    ;;
                CUSTOM|AOSP)
                    # AOSP/custom ROMs: don't touch fstab, they have their own optimizations
                    # Just ensure no dangerous options are set
                    ui_print "  fstab left untouched (ROM has its own optimizations)"
                    ;;
                *)
                    ui_print "  fstab left untouched (unknown ROM)"
                    ;;
            esac

            fstab_found=1
            break
        fi
    done

    if [ "$fstab_found" = "0" ]; then
        ui_print "  No fstab found in ramdisk (custom init may handle mounts)"
    fi
}

# ============================================================================
# Main Execution
# ============================================================================
ROM_TYPE=$(detect_rom)

ui_print " "
ui_print "=== ROM Detection ===";
case "$ROM_TYPE" in
    MIUI)
        ui_print "  ROM: MIUI"
        ui_print "  DSI patch: YES (msm_dsi.phyd_miui)"
        ui_print "  fstab: optimized for MIUI"
        ;;
    HYPEROS)
        ui_print "  ROM: HyperOS"
        ui_print "  DSI patch: YES (msm_dsi.phyd_miui)"
        ui_print "  fstab: optimized for HyperOS"
        ;;
    CUSTOM)
        local custom_name=""
        # Try to identify which custom ROM
        if getprop ro.lineage.version 2>/dev/null | grep -q .; then
            custom_name="LineageOS $(getprop ro.lineage.version 2>/dev/null)"
        elif getprop ro.pixelexperience.version 2>/dev/null | grep -q .; then
            custom_name="PixelOS $(getprop ro.pixelexperience.version 2>/dev/null)"
        elif getprop ro.cr.version 2>/dev/null | grep -q .; then
            custom_name="crDroid $(getprop ro.cr.version 2>/dev/null)"
        elif getprop ro.evolution.version 2>/dev/null | grep -q .; then
            custom_name="Evolution X $(getprop ro.evolution.version 2>/dev/null)"
        elif getprop ro.pa.version 2>/dev/null | grep -q .; then
            custom_name="Paranoid Android $(getprop ro.pa.version 2>/dev/null)"
        elif getprop ro.aex.version 2>/dev/null | grep -q .; then
            custom_name="AOSPExtended $(getprop ro.aex.version 2>/dev/null)"
        elif getprop ro.elixir.version 2>/dev/null | grep -q .; then
            custom_name="Project Elixir $(getprop ro.elixir.version 2>/dev/null)"
        elif getprop ro.rising.version 2>/dev/null | grep -q .; then
            custom_name="RisingOS $(getprop ro.rising.version 2>/dev/null)"
        elif getprop ro.nusantara.version 2>/dev/null | grep -q .; then
            custom_name="Nusantara $(getprop ro.nusantara.version 2>/dev/null)"
        elif getprop ro.spark.version 2>/dev/null | grep -q .; then
            custom_name="Spark OS $(getprop ro.spark.version 2>/dev/null)"
        elif getprop ro.cherish.version 2>/dev/null | grep -q .; then
            custom_name="Cherish OS $(getprop ro.cherish.version 2>/dev/null)"
        elif getprop ro.corvus.version 2>/dev/null | grep -q .; then
            custom_name="Corvus $(getprop ro.corvus.version 2>/dev/null)"
        else
            local flavor="$(getprop ro.build.flavor 2>/dev/null)"
            custom_name="Custom ROM (${flavor:-unknown})"
        fi
        ui_print "  ROM: $custom_name"
        ui_print "  DSI patch: NO (native AOSP DSI)"
        ui_print "  fstab: untouched (ROM-optimized)"
        ;;
    AOSP)
        ui_print "  ROM: AOSP (generic)"
        ui_print "  DSI patch: NO"
        ui_print "  fstab: untouched"
        ;;
    *)
        ui_print "  ROM: Unknown (safe defaults)"
        ui_print "  DSI patch: NO (safe)"
        ui_print "  fstab: untouched"
        ;;
esac
ui_print " ";

# Apply DSI patch (MIUI/HyperOS only)
patch_mi "$ROM_TYPE"

# Apply fstab optimizations
patch_fstab_universal "$ROM_TYPE"