#!/bin/sh
## kyriepatch.sh — MIUI DSI Display Fix
## ONLY called when MIUI is detected by anykernel.sh
## Adds msm_dsi.phyd_miui=1 to kernel cmdline for MIUI compatibility
## This patch is NOT applied on HyperOS or Custom ROMs

cmdl_add() {
    local fh=$split_img/header
    local fhmod=$split_img/header.mod
    if ! grep -q "$1" "$fh" 2>/dev/null; then
        sed -E "s/cmdline=(.*)/cmdline=\1 $1/" "$fh" > "$fhmod"
        mv "$fhmod" "$fh"
    fi
}

cmdl_rm() {
    local fh=$split_img/header
    local fhmod=$split_img/header.mod
    if grep -q "$1" "$fh" 2>/dev/null; then
        sed -E "s/ $1//" "$fh" > "$fhmod"
        mv "$fhmod" "$fh"
    fi
}

# Ensure clean state first
cmdl_rm msm_dsi.phyd_miui=1

# Apply MIUI DSI patch — called only from anykernel.sh when ROM_TYPE=miui
ui_print "  >> Applying MIUI DSI phyd patch..."
cmdl_add msm_dsi.phyd_miui=1
ui_print "  >> msm_dsi.phyd_miui=1 added to cmdline"