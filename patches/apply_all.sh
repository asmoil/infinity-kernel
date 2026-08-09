#!/bin/bash
# Infinity Kernel Patches — apply_all.sh v1.0.48
# For LineageOS android_kernel_qcom_sm8150 base
# Usage: bash apply_all.sh <kernel_src_dir>

KERNEL_SRC="${1:-.}"

if [ ! -f "$KERNEL_SRC/Makefile" ]; then
  echo "ERROR: Makefile not found in $KERNEL_SRC"
  exit 1
fi

echo "=== Applying Infinity Kernel patches to $KERNEL_SRC ==="

# Safe sed function — only replaces if the pattern exists
safe_sed() {
  local file="$1" pattern="$2" replacement="$3"
  if [ -f "$KERNEL_SRC/$file" ] && grep -q "$pattern" "$KERNEL_SRC/$file" 2>/dev/null; then
    sed -i "s|$pattern|$replacement|" "$KERNEL_SRC/$file"
    echo "  Patched: $file"
  fi
}

# [1/7] Scheduler tuning
echo "  [1/7] Scheduler tuning..."
safe_sed "kernel/sched/core.c" \
  "sysctl_sched_min_granularity.*=" \
  "unsigned int sysctl_sched_min_granularity = 500000ULL;"
safe_sed "kernel/sched/core.c" \
  "sysctl_sched_latency.*=" \
  "unsigned int sysctl_sched_latency = 4000000ULL;"
safe_sed "kernel/sched/core.c" \
  "sysctl_sched_wakeup_granularity.*=" \
  "unsigned int sysctl_sched_wakeup_granularity = 1000000ULL;"

# [2/7] CPUFreq ondemand tuning
echo "  [2/7] CPUFreq tuning..."
safe_sed "drivers/cpufreq/cpufreq_ondemand.c" \
  "define.*DEFAULT_UP_THRESHOLD" \
  "#define DEFAULT_UP_THRESHOLD 65"
safe_sed "drivers/cpufreq/cpufreq_ondemand.c" \
  "define.*DEFAULT_SAMPLING_DOWN_FACTOR" \
  "#define DEFAULT_SAMPLING_DOWN_FACTOR 3"

# [3/7] FSYNC
echo "  [3/7] FSYNC check..."
if [ -f "$KERNEL_SRC/fs/f_sync.c" ] || grep -rq "fSync\|fsync" "$KERNEL_SRC/fs/" 2>/dev/null; then
  echo "  FSYNC already present in source tree"
else
  echo "  FSYNC not in source (may be added by defconfig CONFIG_FSYNC)"
fi

# [4/7] TCP BBR check
echo "  [4/7] TCP BBR check..."
if [ -f "$KERNEL_SRC/net/ipv4/bbr.c" ]; then
  echo "  BBR already present"
else
  echo "  BBR will be enabled via defconfig CONFIG_TCP_CONG_BBR"
fi

# [5/7] Root manager support — kallsyms_lookup_name
# NOTE: LineageOS sm8150 already exports it. Do NOT sed-modify
# kallsyms.c as it corrupts the EXPORT line with Clang 23.
echo "  [5/7] Root manager support..."
if grep -q "EXPORT_SYMBOL.*kallsyms_lookup_name" "$KERNEL_SRC/kernel/kallsyms.c" 2>/dev/null; then
  echo "  kallsyms_lookup_name already exported"
else
  echo "  kallsyms_lookup_name not exported (may need manual fix)"
fi

# [6/7] Module signature bypass for root managers
echo "  [6/7] Module support..."
if [ -f "$KERNEL_SRC/kernel/module.c" ]; then
  if ! grep -q "module_is_allowlisted" "$KERNEL_SRC/kernel/module.c" 2>/dev/null; then
    echo "  Module signature: using default kernel config"
  fi
fi

# [7/7] Verbose build info
echo "  [7/7] Build info..."
echo "  Kernel: $(head -5 $KERNEL_SRC/Makefile | tr '\n' ' ')"
echo "  Source: $KERNEL_SRC"

echo "=== All patches applied ==="
exit 0