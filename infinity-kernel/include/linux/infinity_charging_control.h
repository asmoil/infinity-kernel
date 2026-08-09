/*
 * Infinity Kernel - Charging Control Header
 * Copyright (c) 2024 Infinity Kernel Project
 * Licensed under GNU GPL v2.0
 */

#ifndef __INFINITY_CHARGING_CONTROL_H
#define __INFINITY_CHARGING_CONTROL_H

/* Charging states */
enum infinity_charging_state {
	CHARGING_STATE_NORMAL  = 0,
	CHARGING_STATE_BYPASS  = 1,
	CHARGING_STATE_LIMITED = 2,
	CHARGING_STATE_COOLING = 3,
};

/* Gaming mode levels */
enum infinity_gaming_mode {
	GAMING_MODE_OFF     = 0,
	GAMING_MODE_LOW     = 1,
	GAMING_MODE_MEDIUM  = 2,
	GAMING_MODE_HIGH    = 3,
};

/* IOCTL commands for char device */
#define INFINITY_CHARGING_MAGIC  'I'

#define INFINITY_IOCTL_SET_BYPASS       _IOW(INFINITY_CHARGING_MAGIC, 1, int)
#define INFINITY_IOCTL_SET_GAMING_MODE  _IOW(INFINITY_CHARGING_MAGIC, 2, int)
#define INFINITY_IOCTL_GET_BYPASS_STATE _IOR(INFINITY_CHARGING_MAGIC, 3, int)
#define INFINITY_IOCTL_SET_CURRENT      _IOW(INFINITY_CHARGING_MAGIC, 4, int)
#define INFINITY_IOCTL_GET_STATS        _IOR(INFINITY_CHARGING_MAGIC, 5, \
					struct infinity_charging_stats)

/* Statistics structure */
struct infinity_charging_stats {
	int bypass_count;
	unsigned long total_bypass_time_ms;
	enum infinity_charging_state state;
	int charging_enabled;
	int bypass_active;
	enum infinity_gaming_mode gaming_mode;
	int battery_temp_mc;
	int battery_voltage_uv;
	int battery_capacity;
	int current_charge_ma;
};

/* Sysfs paths */
#define INFINITY_CHARGING_SYSFS_PATH \
	"/sys/devices/platform/soc/infinity_charging.infinity_charging/infinity_charging"

/* Default configuration */
#define INFINITY_DEFAULT_MAX_CURRENT_MA      3000
#define INFINITY_GAMING_CURRENT_MA           500
#define INFINITY_COOLDOWN_THRESHOLD_MC       45000
#define INFINITY_RESUME_THRESHOLD_MC         40000
#define INFINITY_BYPASS_MIN_BATTERY_PERCENT  15

#endif /* __INFINITY_CHARGING_CONTROL_H */