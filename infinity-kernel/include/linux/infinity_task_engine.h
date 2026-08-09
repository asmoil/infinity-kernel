/*
 * Infinity Kernel - Task-Aware Performance Engine Header
 * Auto-detects workload type and adjusts CPU/GPU/IO/thermal dynamically
 * For Poco X3 Pro (vayu/bhima) - Snapdragon 732G
 *
 * Copyright (c) 2024 Infinity Kernel Project
 * Licensed under GNU GPL v2.0
 */

#ifndef __INFINITY_TASK_ENGINE_H
#define __INFINITY_TASK_ENGINE_H

/* Task profile identifiers */
enum infinity_task_profile {
	TASK_PROFILE_IDLE		= 0,
	TASK_PROFILE_SOCIAL		= 1,  /* Social media: Telegram, Instagram, etc. */
	TASK_PROFILE_BROWSE		= 2,  /* Web browsing, reading */
	TASK_PROFILE_MEDIA		= 3,  /* Video playback, YouTube, music */
	TASK_PROFILE_NORMAL		= 4,  /* General usage, messaging, light apps */
	TASK_PROFILE_IO_HEAVY		= 5,  /* File operations, installing apps, downloads */
	TASK_PROFILE_GAMING_LIGHT	= 6,  /* Casual games, 2D games */
	TASK_PROFILE_GAMING_HEAVY	= 7,  /* Heavy 3D games, PUBG, Genshin, etc. */
	TASK_PROFILE_CHARGING		= 8,  /* Device charging, prioritize cool charging */
	TASK_PROFILE_COUNT		= 9,
};

/* Profile parameter set */
struct infinity_profile_params {
	/* CPU settings */
	int cpu_max_freq_big;		/* Max freq for big cores (Kryo 470 Gold) in MHz */
	int cpu_max_freq_little;		/* Max freq for LITTLE cores (Kryo 470 Silver) in MHz */
	int min_cpus_online_big;		/* Minimum big cores online */
	int max_cpus_online;		/* Maximum total CPUs online (0 = all 8) */
	int cpu_boost_ms;		/* Touch/input boost duration in ms */

	/* GPU settings */
	int gpu_min_freq_mhz;		/* Min GPU frequency in MHz */
	int gpu_max_freq_mhz;		/* Max GPU frequency in MHz (0 = no limit) */
	int gpu_busy_percent;		/* Target GPU busy percentage */

	/* I/O settings */
	char io_sched[16];		/* IO scheduler name */
	int read_ahead_kb;		/* Read-ahead in KB */
	int ioclass_boost;		/* IO class boost (0-7) */

	/* Memory settings */
	int swappiness;			/* VM swappiness */
	int ksm_sleep_ms;		/* KSM scan interval (0 = disabled) */
	int lru_gen_enabled;		/* Enable MGLRU */

	/* Thermal settings */
	int thermal_limit_mc;		/* Thermal throttle point in millicelsius */
	int thermal_aggressiveness;	/* 0-100, how aggressively throttle */

	/* Charging settings (applied only when TASK_PROFILE_CHARGING) */
	int charge_current_ma;		/* Max charge current in mA */

	/* Scheduler settings */
	int sched_boost;		/* Scheduler boost (0-3) */
	int prefer_idle;		/* Prefer idle core for wakeups */
};

/* Profile switching statistics */
struct infinity_task_stats {
	enum infinity_task_profile current_profile;
	enum infinity_task_profile previous_profile;
	unsigned long profile_switches;
	unsigned long last_switch_ms;
	unsigned long profile_time_ms[TASK_PROFILE_COUNT];
	unsigned int detection_interval_ms;
};

/* Default profile configurations for Snapdragon 732G (SM7325/trinket) */
/* Kryo 470 Gold: up to 2208 MHz, Kryo 470 Silver: up to 1800 MHz */
/* Adreno 618: up to ~750 MHz */

#define TASK_ENGINE_DETECT_INTERVAL_MS	2000  /* Re-detect every 2 seconds */
#define TASK_ENGINE_HYSTERESIS_MS	6000  /* Stay in profile min 6s */
#define TASK_ENGINE_CPU_LOAD_SAMPLE_MS	500   /* CPU load sample window */

/* Sysfs path */
#define INFINITY_TASK_ENGINE_SYSFS_PATH \
	"/sys/devices/platform/infinity_task_engine"

#endif /* __INFINITY_TASK_ENGINE_H */