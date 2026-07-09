#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  Infinity Kernel — Additional Patches
#  This script applies extra patches from the patches/ directory.
#  Place .patch files here and they will be applied in order.
# ═══════════════════════════════════════════════════════════════
set +e

KERNEL_DIR="${1:-.}"
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$KERNEL_DIR" ]; then
    echo "ERROR: Kernel directory not found: $KERNEL_DIR"
    exit 1
fi

cd "$KERNEL_DIR"

# Apply patches in sorted order
PATCH_COUNT=0
PATCH_FAIL=0

for patch_file in $(find "$PATCH_DIR" -maxdepth 1 -name '*.patch' -o -name '*.diff' 2>/dev/null | sort); do
    echo "Applying: $(basename "$patch_file")"
    if patch -p1 --forward --no-backup-if-mismatch < "$patch_file" 2>/dev/null; then
        echo "  OK"
        PATCH_COUNT=$((PATCH_COUNT + 1))
    else
        echo "  SKIP (already applied or does not apply)"
        PATCH_FAIL=$((PATCH_FAIL + 1))
    fi
done

echo "Patches applied: $PATCH_COUNT, skipped: $PATCH_FAIL"

# You can add custom sed/awk fixes below
# Example:
# if [ -f "some/file.c" ]; then
#     sed -i 's/old/new/g' some/file.c
# fi

exit 0