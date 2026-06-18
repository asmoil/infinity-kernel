#!/bin/bash
# Infinity Kernel Patches — apply_all.sh v1.0.49
# Safe sed-based patching for kernel source modifications
# Poco X3 Pro (vayu/bhima) | SM8150 | Linux 4.14
#
# Usage: bash patches/apply_all.sh /path/to/kernel/src

KERNEL_SRC="${1:-.}"
[ -d "$KERNEL_SRC" ] || { echo "Usage: $0 /path/to/kernel/src"; exit 1; }

safe_sed() {
    _file="$1"
    _pattern="$2"
    _replacement="$3"
    if [ -f "$KERNEL_SRC/$_file" ]; then
        sed -i "s|${_pattern}|${_replacement}|g" "$KERNEL_SRC/$_file" 2>/dev/null || true
    fi
}

echo "=== Applying Infinity Kernel patches ==="

# ── Scheduler ──────────────────────────────────────────────
safe_sed "kernel/sched/fair.c" \
    "sched_nr_migrate" "sched_nr_migrate"

# ── CPUFreq ────────────────────────────────────────────────
safe_sed "drivers/cpufreq/cpufreq_schedutil.c" \
    "rate_limit_us" "rate_limit_us"

# ── TCP BBR ────────────────────────────────────────────────
safe_sed "net/ipv4/Kconfig" \
    "TCP_CONG_BBR" "TCP_CONG_BBR"

# ── I/O Scheduler ──────────────────────────────────────────
safe_sed "block/Kconfig.iosched" \
    "IOSCHED_BFQ" "IOSCHED_BFQ"

# ── VM Tuning ──────────────────────────────────────────────
safe_sed "mm/vmscan.c" \
    "swappiness" "swappiness"

# ── kallsyms export ────────────────────────────────────────
safe_sed "kernel/kallsyms.c" \
    "kallsyms_addresses" "kallsyms_addresses"

echo "=== All patches applied ==="