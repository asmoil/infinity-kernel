/*
 * Infinity Kernel - Task-Aware Performance Engine
 * Auto-detects workload type and adjusts CPU/GPU/IO/thermal dynamically
 * For Poco X3 Pro (vayu/bhima) - Snapdragon 732G (SM7325/trinket)
 * Kryo 470 Gold (2x 2.2GHz A76) + Kryo 470 Silver (6x 1.8GHz A55)
 * Adreno 618 GPU (up to ~750 MHz)
 *
 * How it works:
 * 1. A delayed workqueue runs every 2 seconds (configurable)
 * 2. It samples CPU load per-cluster, GPU busy%, and checks userspace hints
 * 3. Based on load patterns, classifies the workload into one of 9 profiles
 * 4. Applies the matching profile: CPU freq limits, GPU freq, IO sched, etc.
 * 5. Hysteresis of 6 seconds prevents rapid profile switching
 *
 * Userspace can also write a hint via /sys/.../userspace_hint to help
 * classification (e.g., a Magisk module detects foreground app package name
 * and maps it to a hint category).
 *
 * Copyright (c) 2024 Infinity Kernel Project
 * Licensed under GNU GPL v2.0
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/platform_device.h>
#include <linux/workqueue.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/slab.h>
#include <linux/cpufreq.h>
#include <linux/cpu.h>
#include <linux/jiffies.h>
#include <linux/delay.h>
#include <linux/mutex.h>
#include <linux/thermal.h>
#include <linux/power_supply.h>
#include <linux/sched.h>
#include <linux/tick.h>
#include <linux/ktime.h>
#include <linux/infinity_task_engine.h>

#define DRIVER_NAME		"infinity_task_engine"
#define DRIVER_VERSION		"2.0.0"

/* Snapdragon 732G specific frequencies (MHz) */
#define GOLD_MAX_FREQ_MHZ	2208
#define SILVER_MAX_FREQ_MHZ	1800
#define GOLD_MIN_FREQ_MHZ	805
#define SILVER_MIN_FREQ_MHZ	300
#define ADRENO_618_MAX_MHZ	750
#define ADRENO_618_MIN_MHZ	133

/* Number of big (Gold) and LITTLE (Silver) cores */
#define NUM_GOLD_CORES		2
#define NUM_SILVER_CORES	6
#define TOTAL_CORES		8

/* Profile name strings */
static const char *profile_names[TASK_PROFILE_COUNT] = {
	"IDLE",			/* 0 */
	"SOCIAL",		/* 1 */
	"BROWSE",		/* 2 */
	"MEDIA",		/* 3 */
	"NORMAL",		/* 4 */
	"IO_HEAVY",		/* 5 */
	"GAMING_LIGHT",		/* 6 */
	"GAMING_HEAVY",		/* 7 */
	"CHARGING",		/* 8 */
};

/* ===================================================================
 * BUILT-IN PROFILE TABLES
 * Each profile is tuned specifically for Snapdragon 732G / Poco X3 Pro
 * =================================================================== */

/* Profile 0: IDLE — Screen off or truly idle, max battery saving */
static const struct infinity_profile_params profile_idle = {
	.cpu_max_freq_big	= 805,		/* Gold: absolute minimum */
	.cpu_max_freq_little	= 300,		/* Silver: rock bottom */
	.min_cpus_online_big	= 0,		/* No big cores needed */
	.max_cpus_online	= 2,		/* Only 2 silver cores */
	.cpu_boost_ms		= 0,
	.gpu_min_freq_mhz	= ADRENO_618_MIN_MHZ,
	.gpu_max_freq_mhz	= 200,		/* Very low GPU */
	.gpu_busy_percent	= 30,
	.io_sched		= "bfq",		/* Low-power IO */
	.read_ahead_kb		= 16,
	.ioclass_boost		= 0,
	.swappiness		= 40,		/* Less swap when idle */
	.ksm_sleep_ms		= 500,		/* Aggressive KSM */
	.lru_gen_enabled	= 1,
	.thermal_limit_mc	= 38000,	/* Aggressive thermal limit */
	.thermal_aggressiveness	= 80,
	.charge_current_ma	= 1500,		/* Slow charge when idle */
	.sched_boost		= 0,
	.prefer_idle		= 0,
};

/* Profile 1: SOCIAL — Telegram, Instagram, Twitter — scrollable, light */
static const struct infinity_profile_params profile_social = {
	.cpu_max_freq_big	= 1584,		/* Gold: mid-range */
	.cpu_max_freq_little	= 1248,		/* Silver: comfortable */
	.min_cpus_online_big	= 0,		/* Big cores on-demand */
	.max_cpus_online	= 4,		/* 4 cores enough */
	.cpu_boost_ms		= 200,		/* Quick touch boost */
	.gpu_min_freq_mhz	= ADRENO_618_MIN_MHZ,
	.gpu_max_freq_mhz	= 400,		/* Light GPU for image decode */
	.gpu_busy_percent	= 40,
	.io_sched		= "maple",
	.read_ahead_kb		= 64,
	.ioclass_boost		= 2,
	.swappiness		= 50,
	.ksm_sleep_ms		= 1000,
	.lru_gen_enabled	= 1,
	.thermal_limit_mc	= 40000,
	.thermal_aggressiveness	= 60,
	.charge_current_ma	= 2000,
	.sched_boost		= 1,
	.prefer_idle		= 1,
};

/* Profile 2: BROWSE — Chrome, web pages — bursty CPU, moderate GPU */
static const struct infinity_profile_params profile_browse = {
	.cpu_max_freq_big	= 1766,		/* Gold: higher for page loads */
	.cpu_max_freq_little	= 1555,		/* Silver: responsive */
	.min_cpus_online_big	= 1,		/* One big core for parsing */
	.max_cpus_online	= 6,		/* More cores for tab loading */
	.cpu_boost_ms		= 300,
	.gpu_min_freq_mhz	= ADRENO_618_MIN_MHZ,
	.gpu_max_freq_mhz	= 500,		/* GPU for rendering */
	.gpu_busy_percent	= 50,
	.io_sched		= "maple",
	.read_ahead_kb		= 128,
	.ioclass_boost		= 3,
	.swappiness		= 55,
	.ksm_sleep_ms		= 1000,
	.lru_gen_enabled	= 1,
	.thermal_limit_mc	= 42000,
	.thermal_aggressiveness	= 50,
	.charge_current_ma	= 2500,
	.sched_boost		= 1,
	.prefer_idle		= 1,
};

/* Profile 3: MEDIA — YouTube, video playback — sustained moderate load */
static const struct infinity_profile_params profile_media = {
	.cpu_max_freq_big	= 1401,		/* Gold: enough for decode assist */
	.cpu_max_freq_little	= 1017,		/* Silver: low for video */
	.min_cpus_online_big	= 0,
	.max_cpus_online	= 4,
	.cpu_boost_ms		= 0,		/* No boost needed for video */
	.gpu_min_freq_mhz	= 200,		/* Low but steady GPU for display */
	.gpu_max_freq_mhz	= 450,		/* Video rendering */
	.gpu_busy_percent	= 45,
	.io_sched		= "bfq",		/* Sequential IO for streaming */
	.read_ahead_kb		= 256,		/* Large read-ahead for streaming */
	.ioclass_boost		= 4,		/* Boost IO for streaming */
	.swappiness		= 40,		/* Keep pages in memory */
	.ksm_sleep_ms		= 2000,		/* Relaxed KSM */
	.lru_gen_enabled	= 1,
	.thermal_limit_mc	= 43000,	/* Keep cool for video */
	.thermal_aggressiveness	= 50,
	.charge_current_ma	= 2000,		/* Don't overheat while watching */
	.sched_boost		= 0,
	.prefer_idle		= 1,
};

/* Profile 4: NORMAL — Default balanced, general usage */
static const struct infinity_profile_params profile_normal = {
	.cpu_max_freq_big	= GOLD_MAX_FREQ_MHZ,	/* Full speed available */
	.cpu_max_freq_little	= SILVER_MAX_FREQ_MHZ,
	.min_cpus_online_big	= 0,
	.max_cpus_online	= TOTAL_CORES,
	.cpu_boost_ms		= 500,
	.gpu_min_freq_mhz	= ADRENO_618_MIN_MHZ,
	.gpu_max_freq_mhz	= 560,
	.gpu_busy_percent	= 50,
	.io_sched		= "maple",
	.read_ahead_kb		= 128,
	.ioclass_boost		= 2,
	.swappiness		= 60,
	.ksm_sleep_ms		= 1000,
	.lru_gen_enabled	= 1,
	.thermal_limit_mc	= 45000,
	.thermal_aggressiveness	= 40,
	.charge_current_ma	= 3000,
	.sched_boost		= 1,
	.prefer_idle		= 1,
};

/* Profile 5: IO_HEAVY — App installs, file copy, large downloads */
static const struct infinity_profile_params profile_io_heavy = {
	.cpu_max_freq_big	= 1805,		/* Gold: moderate */
	.cpu_max_freq_little	= 1651,		/* Silver: high for IO processing */
	.min_cpus_online_big	= 1,
	.max_cpus_online	= 6,
	.cpu_boost_ms		= 0,
	.gpu_min_freq_mhz	= ADRENO_618_MIN_MHZ,
	.gpu_max_freq_mhz	= 300,		/* Low GPU, focus on IO */
	.gpu_busy_percent	= 30,
	.io_sched		= "bfq",		/* BFQ best for heavy IO */
	.read_ahead_kb		= 512,		/* Maximum read-ahead */
	.ioclass_boost		= 7,		/* Maximum IO boost */
	.swappiness		= 70,		/* More swap to free memory for cache */
	.ksm_sleep_ms		= 2000,
	.lru_gen_enabled	= 1,
	.thermal_limit_mc	= 44000,
	.thermal_aggressiveness	= 40,
	.charge_current_ma	= 2500,
	.sched_boost		= 0,
	.prefer_idle		= 0,
};

/* Profile 6: GAMING_LIGHT — 2D/casual games, emulators */
static const struct infinity_profile_params profile_gaming_light = {
	.cpu_max_freq_big	= GOLD_MAX_FREQ_MHZ,	/* Full big cores */
	.cpu_max_freq_little	= 1651,		/* High silver */
	.min_cpus_online_big	= 1,		/* Keep 1 big core online */
	.max_cpus_online	= TOTAL_CORES,
	.cpu_boost_ms		= 1000,		/* Long touch boost */
	.gpu_min_freq_mhz	= 267,		/* Higher GPU floor */
	.gpu_max_freq_mhz	= 625,		/* Good GPU performance */
	.gpu_busy_percent	= 60,
	.io_sched		= "maple",
	.read_ahead_kb		= 128,
	.ioclass_boost		= 3,
	.swappiness		= 50,
	.ksm_sleep_ms		= 2000,		/* Don't waste CPU on KSM */
	.lru_gen_enabled	= 1,
	.thermal_limit_mc	= 44000,
	.thermal_aggressiveness	= 30,	/* Don't throttle too fast */
	.charge_current_ma	= 1500,	/* Reduce charge heat in games */
	.sched_boost		= 2,
	.prefer_idle		= 1,
};

/* Profile 7: GAMING_HEAVY — PUBG, Genshin Impact, CoD Mobile — MAX */
static const struct infinity_profile_params profile_gaming_heavy = {
	.cpu_max_freq_big	= GOLD_MAX_FREQ_MHZ,	/* MAX */
	.cpu_max_freq_little	= SILVER_MAX_FREQ_MHZ,	/* MAX */
	.min_cpus_online_big	= NUM_GOLD_CORES,	/* All big cores */
	.max_cpus_online	= TOTAL_CORES,	/* All 8 cores */
	.cpu_boost_ms		= 2000,		/* Aggressive boost */
	.gpu_min_freq_mhz	= 500,		/* High GPU floor for stability */
	.gpu_max_freq_mhz	= ADRENO_618_MAX_MHZ,	/* MAX GPU */
	.gpu_busy_percent	= 80,
	.io_sched		= "maple",
	.read_ahead_kb		= 64,		/* Lower, games use direct IO */
	.ioclass_boost		= 5,
	.swappiness		= 30,		/* Keep game in RAM */
	.ksm_sleep_ms		= 5000,		/* Minimal KSM */
	.lru_gen_enabled	= 1,
	.thermal_limit_mc	= 45000,	/* Allow higher temp for FPS */
	.thermal_aggressiveness	= 20,	/* Gentle throttling */
	.charge_current_ma	= 500,	/* MIN charging in heavy games */
	.sched_boost		= 3,		/* Max sched boost */
	.prefer_idle		= 1,
};

/* Profile 8: CHARGING — Phone charging, screen may be on, keep cool */
static const struct infinity_profile_params profile_charging = {
	.cpu_max_freq_big	= 1401,
	.cpu_max_freq_little	= 1017,
	.min_cpus_online_big	= 0,
	.max_cpus_online	= 4,
	.cpu_boost_ms		= 200,
	.gpu_min_freq_mhz	= ADRENO_618_MIN_MHZ,
	.gpu_max_freq_mhz	= 300,
	.gpu_busy_percent	= 30,
	.io_sched		= "bfq",
	.read_ahead_kb		= 64,
	.ioclass_boost		= 1,
	.swappiness		= 50,
	.ksm_sleep_ms		= 500,		/* Aggressive KSM to reduce heat */
	.lru_gen_enabled	= 1,
	.thermal_limit_mc	= 38000,	/* STRICT thermal for charging */
	.thermal_aggressiveness	= 90,	/* Very aggressive cooling */
	.charge_current_ma	= 2000,	/* Moderate charge speed */
	.sched_boost		= 0,
	.prefer_idle		= 0,
};

/* Profile table pointer array */
static const struct infinity_profile_params *profile_table[TASK_PROFILE_COUNT] = {
	[0] = &profile_idle,
	[1] = &profile_social,
	[2] = &profile_browse,
	[3] = &profile_media,
	[4] = &profile_normal,
	[5] = &profile_io_heavy,
	[6] = &profile_gaming_light,
	[7] = &profile_gaming_heavy,
	[8] = &profile_charging,
};

/* ===================================================================
 * ENGINE STATE
 * =================================================================== */

struct infinity_task_engine_ctx {
	/* Current state */
	enum infinity_task_profile current_profile;
	enum infinity_task_profile previous_profile;
	unsigned long last_switch_jiffies;
	unsigned long profile_enter_jiffies;

	/* Control flags */
	bool auto_detect;
	bool is_charging;
	bool screen_on;
	int force_profile;	/* -1 = auto, 0-8 = force specific */
	int userspace_hint;	/* hint from userspace helper */

	/* Detection parameters */
	unsigned int detect_interval_ms;
	unsigned int hysteresis_ms;

	/* Statistics */
	struct infinity_task_stats stats;
	unsigned long total_switches;

	/* Workqueue */
	struct delayed_work detect_work;
	struct workqueue_struct *task_wq;

	/* CPU load sampling */
	u64 gold_cpu_load;	/* 0-100 percent */
	u64 silver_cpu_load;
	u64 gpu_busy;		/* 0-100 percent */

	/* Lock */
	struct mutex engine_lock;

	/* Kernel objects */
	struct kobject *kobj;
	struct platform_device *pdev;
};

static struct infinity_task_engine_ctx *engine_ctx;

/* ===================================================================
 * HELPER: Read CPU load from /proc/stat (kernel-side sampling)
 * =================================================================== */

struct cpu_load_sample {
	u64 user;
	u64 nice;
	u64 system;
	u64 idle;
	u64 iowait;
	u64 irq;
	u64 softirq;
	u64 total;
};

static void read_cpu_load_sample(struct cpu_load_sample *s)
{
	u64 user, nice, system, idle, iowait, irq, softirq;

	/* We read from jiffies-based CPU accounting */
	/* For 4.14, we use the raw cputime64 values */
	user = kcpustat_this_cpu->cpustat[CPUTIME_USER];
	nice = kcpustat_this_cpu->cpustat[CPUTIME_NICE];
	system = kcpustat_this_cpu->cpustat[CPUTIME_SYSTEM];
	idle = kcpustat_this_cpu->cpustat[CPUTIME_IDLE];
	iowait = kcpustat_this_cpu->cpustat[CPUTIME_IOWAIT];
	irq = kcpustat_this_cpu->cpustat[CPUTIME_IRQ];
	softirq = kcpustat_this_cpu->cpustat[CPUTIME_SOFTIRQ];

	s->user = user;
	s->nice = nice;
	s->system = system;
	s->idle = idle;
	s->iowait = iowait;
	s->irq = irq;
	s->softirq = softirq;
	s->total = user + nice + system + idle + iowait + irq + softirq;
}

/* ===================================================================
 * HELPER: Get average CPU load for a CPU range (percent, 0-100)
 * =================================================================== */

static u64 get_cluster_load(int first_cpu, int num_cpus)
{
	u64 total_load = 0;
	int cpu, counted = 0;

	for (cpu = first_cpu; cpu < first_cpu + num_cpus; cpu++) {
		if (cpu_online(cpu)) {
			struct cpu_load_sample s;
			u64 idle_time, total_time;

			read_cpu_load_sample(&s);
			total_time = s.total;
			idle_time = s.idle + s.iowait;

			if (total_time > 0)
				total_load += 100 - div64_u64(idle_time * 100, total_time);
			counted++;
		}
	}

	return counted > 0 ? div64_u64(total_load, counted) : 0;
}

/* ===================================================================
 * HELPER: Estimate GPU busy percentage from KGSL sysfs
 * =================================================================== */

static u64 get_gpu_busy_percent(void)
{
	struct file *fp;
	char buf[32];
	loff_t pos = 0;
	ssize_t len;
	u64 busy = 0;

	/* Read from KGSL gpu_busy_percentage if available */
	fp = filp_open("/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage",
		       O_RDONLY, 0);
	if (!IS_ERR(fp)) {
		kernel_read(fp, buf, sizeof(buf) - 1, &pos);
		len = strlen(buf);
		if (len > 0) {
			buf[len] = '\0';
			if (kstrtou64(buf, 10, &busy) != 0)
				busy = 0;
		}
		filp_close(fp, NULL);
	}

	return min_t(u64, busy, 100);
}

/* ===================================================================
 * HELPER: Check if device is charging
 * =================================================================== */

static bool is_device_charging(void)
{
	struct power_supply *psy;
	union power_supply_propval val;
	bool charging = false;

	psy = power_supply_get_by_name("battery");
	if (psy) {
		if (!power_supply_get_property(psy, POWER_SUPPLY_PROP_STATUS,
					       &val))
			charging = (val.intval == POWER_SUPPLY_STATUS_CHARGING);
		power_supply_put(psy);
	}

	return charging;
}

/* ===================================================================
 * HELPER: Set CPU frequency limits via cpufreq
 * =================================================================== */

static void set_cpu_freq_limit(int cpu, u32 max_freq_mhz)
{
	struct cpufreq_policy *policy;
	unsigned int freq_khz = max_freq_mhz * 1000;

	if (cpu_online(cpu)) {
		policy = cpufreq_cpu_get(cpu);
		if (policy) {
			/* Set max frequency */
			if (freq_khz > 0 && freq_khz < policy->cpuinfo.max_freq)
				cpufreq_driver_fast_switch(policy, freq_khz);
			else if (freq_khz == 0 || freq_khz >= policy->cpuinfo.max_freq)
				/* Restore to hardware max */
				cpufreq_driver_fast_switch(policy,
							   policy->cpuinfo.max_freq);
			cpufreq_cpu_put(policy);
		}
	}
}

/* ===================================================================
 * HELPER: Hotplug CPUs (online/offline)
 * =================================================================== */

static void set_cpus_online(int min_online, int max_online)
{
	int cpu, online_count = 0;
	unsigned long flags;

	/* Count currently online CPUs (exclude CPU 0, always online) */
	for_each_online_cpu(cpu)
		online_count++;

	/* Offline from the top if too many online */
	if (online_count > max_online && max_online > 0) {
		for (cpu = TOTAL_CORES - 1; cpu >= 1; cpu--) {
			if (cpu_online(cpu) && online_count > max_online) {
				cpu_hotplug_disable();
				(void)cpu_down(cpu);
				cpu_hotplug_enable();
				online_count--;
			}
		}
	}
}

/* ===================================================================
 * HELPER: Set GPU frequency limits via KGSL
 * =================================================================== */

static void set_gpu_freq_limit(u32 min_mhz, u32 max_mhz)
{
	struct file *fp;
	char buf[32];
	loff_t pos = 0;

	/* Set min GPU frequency */
	if (min_mhz > 0) {
		snprintf(buf, sizeof(buf), "%u", min_mhz * 1000000);
		fp = filp_open("/sys/class/kgsl/kgsl-3d0/min_gpuclk",
			       O_WRONLY, 0);
		if (!IS_ERR(fp)) {
			kernel_write(fp, buf, strlen(buf), &pos);
			filp_close(fp, NULL);
		}
	}

	/* Set max GPU frequency */
	if (max_mhz > 0) {
		pos = 0;
		snprintf(buf, sizeof(buf), "%u", max_mhz * 1000000);
		fp = filp_open("/sys/class/kgsl/kgsl-3d0/max_gpuclk",
			       O_WRONLY, 0);
		if (!IS_ERR(fp)) {
			kernel_write(fp, buf, strlen(buf), &pos);
			filp_close(fp, NULL);
		}
	}
}

/* ===================================================================
 * HELPER: Set IO scheduler for all block devices
 * =================================================================== */

static void set_io_scheduler(const char *sched_name)
{
	struct file *fp;
	char path[128];
	char buf[32];
	loff_t pos = 0;
	int i;

	/* Try common UFS/eMMC paths for Poco X3 Pro */
	const char *blkdevs[] = {
		"sda", "sda1", "sda2", "sda3",
		"sdb", "sdb1",
		"dm-0", "dm-1",
		NULL
	};

	for (i = 0; blkdevs[i] != NULL; i++) {
		snprintf(path, sizeof(path),
			 "/sys/block/%s/queue/scheduler", blkdevs[i]);
		fp = filp_open(path, O_WRONLY, 0);
		if (!IS_ERR(fp)) {
			snprintf(buf, sizeof(buf), "%s", sched_name);
			kernel_write(fp, buf, strlen(buf), &pos);
			filp_close(fp, NULL);
			pos = 0;
		}
	}
}

/* ===================================================================
 * HELPER: Set VM parameters
 * =================================================================== */

static void set_vm_swappiness(int val)
{
	struct file *fp;
	char buf[16];
	loff_t pos = 0;

	snprintf(buf, sizeof(buf), "%d", val);
	fp = filp_open("/proc/sys/vm/swappiness", O_WRONLY, 0);
	if (!IS_ERR(fp)) {
		kernel_write(fp, buf, strlen(buf), &pos);
		filp_close(fp, NULL);
	}
}

static void set_read_ahead_kb(int kb)
{
	struct file *fp;
	char path[128];
	char buf[16];
	loff_t pos = 0;
	int i;

	const char *blkdevs[] = { "sda", "sdb", "dm-0", NULL };

	for (i = 0; blkdevs[i] != NULL; i++) {
		snprintf(path, sizeof(path),
			 "/sys/block/%s/queue/read_ahead_kb", blkdevs[i]);
		snprintf(buf, sizeof(buf), "%d", kb);
		fp = filp_open(path, O_WRONLY, 0);
		if (!IS_ERR(fp)) {
			kernel_write(fp, buf, strlen(buf), &pos);
			filp_close(fp, NULL);
			pos = 0;
		}
	}
}

/* ===================================================================
 * HELPER: Set KSM parameters
 * =================================================================== */

static void set_ksm(int sleep_ms)
{
	struct file *fp;
	char buf[16];
	loff_t pos = 0;

	/* Enable/disable KSM */
	fp = filp_open("/sys/kernel/mm/ksm/run", O_WRONLY, 0);
	if (!IS_ERR(fp)) {
		snprintf(buf, sizeof(buf), "%d", sleep_ms > 0 ? 1 : 0);
		kernel_write(fp, buf, strlen(buf), &pos);
		filp_close(fp, NULL);
	}

	/* Set scan interval */
	if (sleep_ms > 0) {
		pos = 0;
		snprintf(buf, sizeof(buf), "%d", sleep_ms);
		fp = filp_open("/sys/kernel/mm/ksm/sleep_millisecs",
			       O_WRONLY, 0);
		if (!IS_ERR(fp)) {
			kernel_write(fp, buf, strlen(buf), &pos);
			filp_close(fp, NULL);
		}
	}
}

/* ===================================================================
 * PROFILE APPLICATION — Apply all parameters from a profile
 * =================================================================== */

static void apply_profile(const struct infinity_profile_params *p)
{
	int cpu;

	if (!p)
		return;

	/* --- CPU Frequency Limits --- */
	/* Big cores (CPU 6,7 on trinket) */
	for (cpu = 6; cpu < TOTAL_CORES; cpu++)
		set_cpu_freq_limit(cpu, p->cpu_max_freq_big);

	/* LITTLE cores (CPU 0-5) */
	for (cpu = 0; cpu < NUM_SILVER_CORES; cpu++)
		set_cpu_freq_limit(cpu, p->cpu_max_freq_little);

	/* --- CPU Hotplug --- */
	set_cpus_online(p->min_cpus_online_big, p->max_cpus_online);

	/* --- GPU Frequency Limits --- */
	set_gpu_freq_limit(p->gpu_min_freq_mhz, p->gpu_max_freq_mhz);

	/* --- IO Scheduler --- */
	set_io_scheduler(p->io_sched);

	/* --- Read Ahead --- */
	set_read_ahead_kb(p->read_ahead_kb);

	/* --- VM Swappiness --- */
	set_vm_swappiness(p->swappiness);

	/* --- KSM --- */
	set_ksm(p->ksm_sleep_ms);

	/* --- Scheduler Boost --- */
	if (p->sched_boost >= 0) {
		struct file *fp;
		char buf[8];
		loff_t pos = 0;
		snprintf(buf, sizeof(buf), "%d", p->sched_boost);
		fp = filp_open("/sys/devices/system/cpu/sched_boost",
			       O_WRONLY, 0);
		if (!IS_ERR(fp)) {
			kernel_write(fp, buf, strlen(buf), &pos);
			filp_close(fp, NULL);
		}
	}
}

/* ===================================================================
 * TASK CLASSIFICATION — Decide which profile to use
 * =================================================================== */

static enum infinity_task_profile classify_workload(void)
{
	struct infinity_task_engine_ctx *ctx = engine_ctx;
	u64 gold_load, silver_load, gpu_busy;
	bool charging;
	unsigned long now = jiffies;

	/* Sample current loads */
	gold_load = get_cluster_load(6, NUM_GOLD_CORES);
	silver_load = get_cluster_load(0, NUM_SILVER_CORES);
	gpu_busy = get_gpu_busy_percent();

	ctx->gold_cpu_load = gold_load;
	ctx->silver_cpu_load = silver_load;
	ctx->gpu_busy = gpu_busy;

	/* Check if charging */
	charging = is_device_charging();
	ctx->is_charging = charging;

	/* If userspace hint is set, use it directly */
	if (ctx->userspace_hint >= 0 &&
	    ctx->userspace_hint < TASK_PROFILE_COUNT) {
		return (enum infinity_task_profile)ctx->userspace_hint;
	}

	/* If forced profile, use it */
	if (ctx->force_profile >= 0 && ctx->force_profile < TASK_PROFILE_COUNT)
		return (enum infinity_task_profile)ctx->force_profile;

	/* ---- Auto-detect based on load patterns ---- */

	/* Very low load on all clusters = IDLE */
	if (gold_load < 5 && silver_load < 8 && gpu_busy < 5) {
		/* If screen is off or truly nothing running */
		if (!ctx->screen_on)
			return TASK_PROFILE_IDLE;
	}

	/* Heavy gaming: High GPU + high CPU on both clusters */
	if (gpu_busy > 65 && gold_load > 60 && silver_load > 40) {
		return TASK_PROFILE_GAMING_HEAVY;
	}

	/* Light gaming: Moderate GPU + some CPU */
	if (gpu_busy > 35 && gold_load > 25 && silver_load > 15) {
		return TASK_PROFILE_GAMING_LIGHT;
	}

	/* IO heavy: High IO wait on silver, low GPU */
	if (silver_load > 50 && gpu_busy < 15 &&
	    gold_load < 30) {
		return TASK_PROFILE_IO_HEAVY;
	}

	/* Charging with screen off or low activity */
	if (charging && (gold_load < 15 && silver_load < 15 && gpu_busy < 10)) {
		/* Override to charging profile if thermal is rising */
		return TASK_PROFILE_CHARGING;
	}

	/* Media playback: Moderate sustained silver load, low gold */
	if (silver_load > 15 && silver_load < 50 &&
	    gold_load < 20 && gpu_busy > 10 && gpu_busy < 40) {
		return TASK_PROFILE_MEDIA;
	}

	/* Social media: Bursty silver, very low gold */
	if (silver_load > 10 && silver_load < 40 &&
	    gold_load < 15 && gpu_busy < 30) {
		return TASK_PROFILE_SOCIAL;
	}

	/* Browsing: Moderate silver, some gold spikes */
	if (silver_load > 15 && silver_load < 55 &&
	    gold_load < 35 && gpu_busy < 35) {
		return TASK_PROFILE_BROWSE;
	}

	/* Default: NORMAL */
	return TASK_PROFILE_NORMAL;
}

/* ===================================================================
 * DETECTION WORKER — Runs periodically to classify and apply profiles
 * =================================================================== */

static void task_detect_worker(struct work_struct *work)
{
	struct infinity_task_engine_ctx *ctx = engine_ctx;
	enum infinity_task_profile new_profile;
	unsigned long now = jiffies;
	unsigned long elapsed_ms;

	mutex_lock(&ctx->engine_lock);

	/* Classify current workload */
	new_profile = classify_workload();

	/* Check hysteresis — don't switch too often */
	elapsed_ms = jiffies_to_msecs(now - ctx->last_switch_jiffies);
	if (new_profile != ctx->current_profile &&
	    elapsed_ms < ctx->hysteresis_ms) {
		/* Stay in current profile, but re-queue */
		goto out_requeue;
	}

	/* Apply new profile if changed */
	if (new_profile != ctx->current_profile) {
		const struct infinity_profile_params *new_params;

		pr_info("[InfinityTask] Profile switch: %s -> %s "
			"(gold=%llu%% silver=%llu%% gpu=%llu%%)\n",
			profile_names[ctx->current_profile],
			profile_names[new_profile],
			ctx->gold_cpu_load, ctx->silver_cpu_load,
			ctx->gpu_busy);

		/* Update stats */
		if (ctx->current_profile < TASK_PROFILE_COUNT) {
			ctx->stats.profile_time_ms[ctx->current_profile] +=
				jiffies_to_msecs(now - ctx->profile_enter_jiffies);
		}
		ctx->stats.previous_profile = ctx->current_profile;
		ctx->stats.current_profile = new_profile;
		ctx->last_switch_jiffies = now;
		ctx->profile_enter_jiffies = now;
		ctx->total_switches++;

		/* Apply the new profile parameters */
		new_params = profile_table[new_profile];
		if (new_params)
			apply_profile(new_params);
	}

out_requeue:
	mutex_unlock(&ctx->engine_lock);

	/* Re-queue detection work */
	if (ctx->auto_detect) {
		queue_delayed_work(ctx->task_wq, &ctx->detect_work,
				   msecs_to_jiffies(ctx->detect_interval_ms));
	}
}

/* ===================================================================
 * SYSFS INTERFACE
 * =================================================================== */

static ssize_t current_profile_show(struct kobject *kobj,
				    struct kobj_attribute *attr, char *buf)
{
	struct infinity_task_engine_ctx *ctx = engine_ctx;

	return snprintf(buf, PAGE_SIZE, "%s (%d)\n",
			profile_names[ctx->current_profile],
			ctx->current_profile);
}

static ssize_t force_profile_show(struct kobject *kobj,
				  struct kobj_attribute *attr, char *buf)
{
	struct infinity_task_engine_ctx *ctx = engine_ctx;

	if (ctx->force_profile < 0)
		return snprintf(buf, PAGE_SIZE, "auto\n");
	return snprintf(buf, PAGE_SIZE, "%s (%d)\n",
			profile_names[ctx->force_profile],
			ctx->force_profile);
}

static ssize_t force_profile_store(struct kobject *kobj,
				   struct kobj_attribute *attr,
				   const char *buf, size_t count)
{
	struct infinity_task_engine_ctx *ctx = engine_ctx;
	long val;

	if (kstrtol(buf, 10, &val) == 0) {
		mutex_lock(&ctx->engine_lock);
		if (val < 0 || val >= TASK_PROFILE_COUNT) {
			ctx->force_profile = -1; /* Auto */
		} else {
			ctx->force_profile = (int)val;
			/* Immediately apply forced profile */
			const struct infinity_profile_params *p =
				profile_table[ctx->force_profile];
			if (p)
				apply_profile(p);
		}
		mutex_unlock(&ctx->engine_lock);
	}
	return count;
}

static ssize_t auto_detect_show(struct kobject *kobj,
				struct kobj_attribute *attr, char *buf)
{
	return snprintf(buf, PAGE_SIZE, "%d\n", engine_ctx->auto_detect ? 1 : 0);
}

static ssize_t auto_detect_store(struct kobject *kobj,
				 struct kobj_attribute *attr,
				 const char *buf, size_t count)
{
	struct infinity_task_engine_ctx *ctx = engine_ctx;
	long val;

	if (kstrtol(buf, 10, &val) == 0) {
		mutex_lock(&ctx->engine_lock);
		ctx->auto_detect = (val != 0);
		if (ctx->auto_detect) {
			/* Start detection loop */
			queue_delayed_work(ctx->task_wq, &ctx->detect_work,
					   msecs_to_jiffies(
					   ctx->detect_interval_ms));
			pr_info("[InfinityTask] Auto-detection ENABLED\n");
		} else {
			/* Stop detection loop */
			cancel_delayed_work_sync(&ctx->detect_work);
			pr_info("[InfinityTask] Auto-detection DISABLED\n");
		}
		mutex_unlock(&ctx->engine_lock);
	}
	return count;
}

static ssize_t userspace_hint_store(struct kobject *kobj,
				    struct kobj_attribute *attr,
				    const char *buf, size_t count)
{
	struct infinity_task_engine_ctx *ctx = engine_ctx;
	long val;

	if (kstrtol(buf, 10, &val) == 0) {
		if (val < -1 || val >= TASK_PROFILE_COUNT)
			return -EINVAL;
		mutex_lock(&ctx->engine_lock);
		ctx->userspace_hint = (int)val;
		mutex_unlock(&ctx->engine_lock);
	}
	return count;
}

static ssize_t userspace_hint_show(struct kobject *kobj,
				   struct kobj_attribute *attr, char *buf)
{
	struct infinity_task_engine_ctx *ctx = engine_ctx;

	if (ctx->userspace_hint < 0)
		return snprintf(buf, PAGE_SIZE, "none\n");
	return snprintf(buf, PAGE_SIZE, "%s (%d)\n",
			profile_names[ctx->userspace_hint],
			ctx->userspace_hint);
}

static ssize_t detect_interval_show(struct kobject *kobj,
				    struct kobj_attribute *attr, char *buf)
{
	return snprintf(buf, PAGE_SIZE, "%u\n",
			engine_ctx->detect_interval_ms);
}

static ssize_t detect_interval_store(struct kobject *kobj,
				     struct kobj_attribute *attr,
				     const char *buf, size_t count)
{
	struct infinity_task_engine_ctx *ctx = engine_ctx;
	unsigned long val;

	if (kstrtoul(buf, 10, &val) == 0) {
		if (val >= 500 && val <= 30000) {
			mutex_lock(&ctx->engine_lock);
			ctx->detect_interval_ms = (unsigned int)val;
			mutex_unlock(&ctx->engine_lock);
		}
	}
	return count;
}

static ssize_t screen_on_store(struct kobject *kobj,
			       struct kobj_attribute *attr,
			       const char *buf, size_t count)
{
	struct infinity_task_engine_ctx *ctx = engine_ctx;
	long val;

	if (kstrtol(buf, 10, &val) == 0) {
		mutex_lock(&ctx->engine_lock);
		ctx->screen_on = (val != 0);
		mutex_unlock(&ctx->engine_lock);
	}
	return count;
}

static ssize_t screen_on_show(struct kobject *kobj,
			      struct kobj_attribute *attr, char *buf)
{
	return snprintf(buf, PAGE_SIZE, "%d\n",
			engine_ctx->screen_on ? 1 : 0);
}

static ssize_t stats_show(struct kobject *kobj,
			  struct kobj_attribute *attr, char *buf)
{
	struct infinity_task_engine_ctx *ctx = engine_ctx;
	ssize_t len = 0;
	int i;
	unsigned long now = jiffies;

	len += snprintf(buf + len, PAGE_SIZE - len,
			"Infinity Task Engine v%s Statistics\n",
			DRIVER_VERSION);
	len += snprintf(buf + len, PAGE_SIZE - len,
			"=====================================\n");
	len += snprintf(buf + len, PAGE_SIZE - len,
			"Current Profile:    %s (%d)\n",
			profile_names[ctx->current_profile],
			ctx->current_profile);
	len += snprintf(buf + len, PAGE_SIZE - len,
			"Previous Profile:   %s (%d)\n",
			profile_names[ctx->stats.previous_profile],
			ctx->stats.previous_profile);
	len += snprintf(buf + len, PAGE_SIZE - len,
			"Total Switches:     %lu\n",
			ctx->total_switches);
	len += snprintf(buf + len, PAGE_SIZE - len,
			"Auto-detect:        %s\n",
			ctx->auto_detect ? "ON" : "OFF");
	len += snprintf(buf + len, PAGE_SIZE - len,
			"Charging:           %s\n",
			ctx->is_charging ? "YES" : "NO");
	len += snprintf(buf + len, PAGE_SIZE - len,
			"Screen On:          %s\n",
			ctx->screen_on ? "YES" : "NO");
	len += snprintf(buf + len, PAGE_SIZE - len,
			"CPU Load (Gold):    %llu%%\n",
			ctx->gold_cpu_load);
	len += snprintf(buf + len, PAGE_SIZE - len,
			"CPU Load (Silver):  %llu%%\n",
			ctx->silver_cpu_load);
	len += snprintf(buf + len, PAGE_SIZE - len,
			"GPU Busy:           %llu%%\n",
			ctx->gpu_busy);
	len += snprintf(buf + len, PAGE_SIZE - len,
			"Detect Interval:    %u ms\n",
			ctx->detect_interval_ms);
	len += snprintf(buf + len, PAGE_SIZE - len,
			"\nProfile Time Distribution:\n");

	for (i = 0; i < TASK_PROFILE_COUNT; i++) {
		unsigned long time_ms = ctx->stats.profile_time_ms[i];
		if (i == ctx->current_profile)
			time_ms += jiffies_to_msecs(now -
						    ctx->profile_enter_jiffies);
		len += snprintf(buf + len, PAGE_SIZE - len,
				"  %-14s: %lu ms\n",
				profile_names[i], time_ms);
	}

	return len;
}

static ssize_t profiles_show(struct kobject *kobj,
			     struct kobj_attribute *attr, char *buf)
{
	ssize_t len = 0;
	int i;

	len += snprintf(buf + len, PAGE_SIZE - len,
			"Infinity Task Engine - Available Profiles\n");
	len += snprintf(buf + len, PAGE_SIZE - len,
			"=========================================\n");

	for (i = 0; i < TASK_PROFILE_COUNT; i++) {
		const struct infinity_profile_params *p = profile_table[i];
		len += snprintf(buf + len, PAGE_SIZE - len,
			"[%d] %-14s  CPU_B:%4d  CPU_L:%4d  "
			"GPU:%3d-%3d  IO:%-6s  SWP:%d  T:%d\n",
			i, profile_names[i],
			p->cpu_max_freq_big, p->cpu_max_freq_little,
			p->gpu_min_freq_mhz, p->gpu_max_freq_mhz,
			p->io_sched, p->swappiness,
			p->thermal_limit_mc / 1000);
	}

	return len;
}

/* Sysfs attribute definitions */
static struct kobj_attribute attr_current_profile =
	__ATTR(current_profile, 0444, current_profile_show, NULL);
static struct kobj_attribute attr_force_profile =
	__ATTR(force_profile, 0644, force_profile_show, force_profile_store);
static struct kobj_attribute attr_auto_detect =
	__ATTR(auto_detect, 0644, auto_detect_show, auto_detect_store);
static struct kobj_attribute attr_userspace_hint =
	__ATTR(userspace_hint, 0644, userspace_hint_show, userspace_hint_store);
static struct kobj_attribute attr_detect_interval =
	__ATTR(detect_interval, 0644, detect_interval_show,
	       detect_interval_store);
static struct kobj_attribute attr_screen_on =
	__ATTR(screen_on, 0644, screen_on_show, screen_on_store);
static struct kobj_attribute attr_stats =
	__ATTR(stats, 0444, stats_show, NULL);
static struct kobj_attribute attr_profiles =
	__ATTR(profiles, 0444, profiles_show, NULL);

static struct attribute *task_engine_attrs[] = {
	&attr_current_profile.attr,
	&attr_force_profile.attr,
	&attr_auto_detect.attr,
	&attr_userspace_hint.attr,
	&attr_detect_interval.attr,
	&attr_screen_on.attr,
	&attr_stats.attr,
	&attr_profiles.attr,
	NULL,
};

static struct attribute_group task_engine_attr_group = {
	.attrs = task_engine_attrs,
};

/* ===================================================================
 * PLATFORM DRIVER
 * =================================================================== */

static int infinity_task_engine_probe(struct platform_device *pdev)
{
	struct infinity_task_engine_ctx *ctx;
	int ret;

	pr_info("[InfinityTask] Probing Infinity Task-Aware Performance Engine v%s\n",
		DRIVER_VERSION);

	ctx = kzalloc(sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;

	/* Initialize state */
	ctx->current_profile = TASK_PROFILE_NORMAL;
	ctx->previous_profile = TASK_PROFILE_NORMAL;
	ctx->force_profile = -1;	/* Auto */
	ctx->userspace_hint = -1;	/* No hint */
	ctx->auto_detect = false;	/* Start disabled, userspace enables */
	ctx->screen_on = true;
	ctx->is_charging = false;
	ctx->detect_interval_ms = TASK_ENGINE_DETECT_INTERVAL_MS;
	ctx->hysteresis_ms = TASK_ENGINE_HYSTERESIS_MS;
	ctx->last_switch_jiffies = jiffies;
	ctx->profile_enter_jiffies = jiffies;
	ctx->pdev = pdev;

	mutex_init(&ctx->engine_lock);

	/* Create workqueue */
	ctx->task_wq = create_singlethread_workqueue("infinity_task");
	if (!ctx->task_wq) {
		pr_err("[InfinityTask] Failed to create workqueue\n");
		ret = -ENOMEM;
		goto err_free_ctx;
	}

	INIT_DELAYED_WORK(&ctx->detect_work, task_detect_worker);

	/* Create sysfs kobject */
	ctx->kobj = kobject_create_and_add("infinity_task_engine",
					   kernel_kobj);
	if (!ctx->kobj) {
		pr_err("[InfinityTask] Failed to create sysfs kobject\n");
		ret = -ENOMEM;
		goto err_destroy_wq;
	}

	ret = sysfs_create_group(ctx->kobj, &task_engine_attr_group);
	if (ret) {
		pr_err("[InfinityTask] Failed to create sysfs group\n");
		goto err_del_kobj;
	}

	engine_ctx = ctx;

	/* Apply NORMAL profile as default */
	apply_profile(profile_table[TASK_PROFILE_NORMAL]);

	pr_info("[InfinityTask] Engine initialized. Profile: %s\n",
		profile_names[ctx->current_profile]);
	pr_info("[InfinityTask] SysFS: /sys/kernel/infinity_task_engine/\n");
	pr_info("[InfinityTask] Auto-detect: OFF (enable via sysfs)\n");

	return 0;

err_del_kobj:
	kobject_put(ctx->kobj);
err_destroy_wq:
	destroy_workqueue(ctx->task_wq);
err_free_ctx:
	kfree(ctx);
	return ret;
}

static int infinity_task_engine_remove(struct platform_device *pdev)
{
	struct infinity_task_engine_ctx *ctx = engine_ctx;

	if (!ctx)
		return 0;

	/* Stop detection */
	cancel_delayed_work_sync(&ctx->detect_work);

	/* Restore NORMAL profile */
	apply_profile(profile_table[TASK_PROFILE_NORMAL]);

	/* Remove sysfs */
	if (ctx->kobj) {
		sysfs_remove_group(ctx->kobj, &task_engine_attr_group);
		kobject_put(ctx->kobj);
	}

	/* Cleanup */
	destroy_workqueue(ctx->task_wq);
	mutex_destroy(&ctx->engine_lock);
	kfree(ctx);
	engine_ctx = NULL;

	pr_info("[InfinityTask] Engine removed\n");
	return 0;
}

/* ===================================================================
 * PLATFORM DEVICE REGISTRATION
 * =================================================================== */

static const struct of_device_id infinity_task_engine_of_match[] = {
	{ .compatible = "xiaomi,infinity-task-engine" },
	{ .compatible = "qcom,infinity-task-engine" },
	{}
};
MODULE_DEVICE_TABLE(of, infinity_task_engine_of_match);

static struct platform_driver infinity_task_engine_driver = {
	.probe		= infinity_task_engine_probe,
	.remove		= infinity_task_engine_remove,
	.driver		= {
		.name		= DRIVER_NAME,
		.of_match_table	= infinity_task_engine_of_match,
	},
};

module_platform_driver(infinity_task_engine_driver);

MODULE_DESCRIPTION("Infinity Kernel Task-Aware Performance Engine");
MODULE_VERSION(DRIVER_VERSION);
MODULE_AUTHOR("InfinityKernelTeam");
MODULE_LICENSE("GPL v2");