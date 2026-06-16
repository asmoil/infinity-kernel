#!/system/bin/sh
# Infinity Kernel Init Script v1.0.36
# Poco X3 Pro (vayu/bhima) | SM8250-AC
# BBR, Maple/BFQ, ZRAM 5GB LZ4, KSM, FSYNC, VM tuning

LOG_TAG="infinity_init"

echo "bbr" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null

for dev in /sys/block/*/queue/scheduler; do
  if grep -q "\[maple\]" "$dev" 2>/dev/null; then
    echo "maple" > "$dev"
  elif grep -q "bfq" "$dev" 2>/dev/null; then
    echo "bfq" > "$dev"
  fi
done

if [ -f /sys/block/zram0/disksize ]; then
  swapoff /dev/zram0 2>/dev/null
  echo "5G" > /sys/block/zram0/disksize 2>/dev/null
  echo "lz4" > /sys/block/zram0/comp_algorithm 2>/dev/null
  mkswap /dev/zram0 2>/dev/null
  swapon -p 32767 /dev/zram0 2>/dev/null
fi

echo "1000" > /sys/kernel/mm/ksm/sleep_millisecs 2>/dev/null
echo "200"   > /sys/kernel/mm/ksm/pages_to_scan    2>/dev/null
echo "1"     > /sys/kernel/mm/ksm/run             2>/dev/null

echo "1" > /sys/fs/fSync/enable 2>/dev/null

echo "50"    > /proc/sys/vm/swappiness          2>/dev/null
echo "1000"  > /proc/sys/vm/vfs_cache_pressure  2>/dev/null
echo "3"     > /proc/sys/vm/dirty_ratio          2>/dev/null
echo "10"    > /proc/sys/vm/dirty_background_ratio 2>/dev/null
echo "500"   > /proc/sys/vm/dirty_writeback_centisecs  2>/dev/null
echo "0"     > /proc/sys/vm/oom_kill_allocating_task 2>/dev/null
echo "1" > /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null

exit 0
