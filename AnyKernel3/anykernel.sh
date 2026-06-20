# AnyKernel3 flasher for Infinity Kernel
# Target: Poco X3 Pro (vayu/bhima)

kernel.string=Infinity Kernel by asmoil
do.devicecheck=1
do.systemless=1

# ── Device check ────────────────────────────────────
supported.versions=13
supported.patchlevels=2023-01 2023-02 2023-03 2023-04 2023-05 2023-06 2023-07 2023-08 2023-09 2023-10 2023-11 2023-12 2024-01 2024-02 2024-03 2024-04 2024-05 2024-06 2024-07 2024-08 2024-09 2024-10 2024-11 2024-12 2025-01 2025-02 2025-03 2025-04 2025-05 2025-06

# ── Slot device (A/B partition) ─────────────────────
is_slot_device=1
slot_select=1
no_emui_warning=1
no_verity_warning=1
patch_vbmeta_flag=1

# ── Flash ─────────────────────────────────────────
flashbootimg=1

# ── Kernel image ───────────────────────────────────
backup_file=boot.img

# ── Init script ────────────────────────────────────
init_post_flash.tools/infinity_init.sh
