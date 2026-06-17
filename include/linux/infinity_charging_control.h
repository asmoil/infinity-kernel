/*
 * Infinity Kernel Charging Bypass Control Header
 * Copyright (C) 2024 Infinity Kernel Team
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 and
 * only version 2 as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 */

#ifndef __LINUX_INFINITY_CHARGING_CONTROL_H
#define __LINUX_INFINITY_CHARGING_CONTROL_H

#include <linux/types.h>
#include <linux/ioctl.h>
#include <linux/device.h>

/**
 * enum infinity_charging_mode - Charging bypass mode selection
 * @CHARGING_MODE_OFF:    Normal charging, no bypass active
 * @CHARGING_MODE_LIGHT:  Pause at 80%, thermal limit 45C, -10% current
 * @CHARGING_MODE_BALANCED: Pause at 70%, thermal limit 40C, -30% current
 * @CHARGING_MODE_EXTREME: Pause at 60%, thermal limit 35C, -50% current
 * @CHARGING_MODE_ULTRA:  Pause at 50%, thermal limit 35C, -70% current
 */
enum infinity_charging_mode {
	CHARGING_MODE_OFF		= 0,
	CHARGING_MODE_LIGHT		= 1,
	CHARGING_MODE_BALANCED		= 2,
	CHARGING_MODE_EXTREME		= 3,
	CHARGING_MODE_ULTRA		= 4,
};

/**
 * enum infinity_thermal_limit - Thermal throttle thresholds in Celsius
 * @THERMAL_LIMIT_DISABLED: No thermal monitoring
 * @THERMAL_LIMIT_45C:      Throttle at 45 degrees C
 * @THERMAL_LIMIT_40C:      Throttle at 40 degrees C
 * @THERMAL_LIMIT_35C:      Throttle at 35 degrees C
 */
enum infinity_thermal_limit {
	THERMAL_LIMIT_DISABLED		= 0,
	THERMAL_LIMIT_45C		= 45,
	THERMAL_LIMIT_40C		= 40,
	THERMAL_LIMIT_35C		= 35,
};

/**
 * struct infinity_charging_status - Runtime status of the charging controller
 * @mode:             Current charging bypass mode
 * @battery_voltage:  Battery voltage in microvolts (uV)
 * @battery_current:  Battery current in microamps (uA)
 * @battery_temp:     Battery temperature in millidegrees Celsius (mC)
 * @is_charging:      True if charging is currently enabled
 * @thermal_throttled: True if charging is paused due to thermal limit
 * @bypass_active:    True if the bypass controller has paused charging
 */
struct infinity_charging_status {
	__u32 mode;
	__s32 battery_voltage;
	__s32 battery_current;
	__s32 battery_temp;
	__u8  is_charging;
	__u8  thermal_throttled;
	__u8  bypass_active;
};

/*
 * IOCTL magic number and command definitions
 * Accessed via the infinity-charging misc device node
 */
#define INFINITY_CHARGING_MAGIC	0xCC

/**
 * INFINITY_CHARGING_SET_MODE - Set the charging bypass mode
 * @arg: Pointer to enum infinity_charging_mode (int)
 */
#define INFINITY_CHARGING_SET_MODE		_IOW(INFINITY_CHARGING_MAGIC, 1, int)

/**
 * INFINITY_CHARGING_GET_STATUS - Retrieve full charging status
 * @arg: Pointer to struct infinity_charging_status
 */
#define INFINITY_CHARGING_GET_STATUS		_IOR(INFINITY_CHARGING_MAGIC, 2, \
						struct infinity_charging_status)

/**
 * INFINITY_CHARGING_SET_THERMAL_LIMIT - Override thermal limit in Celsius
 * @arg: Pointer to int (temperature)
 */
#define INFINITY_CHARGING_SET_THERMAL_LIMIT	_IOW(INFINITY_CHARGING_MAGIC, 3, int)

/**
 * INFINITY_CHARGING_SET_AUTO_RESUME - Set auto-resume SoC threshold (%)
 * @arg: Pointer to int (percentage 0-100)
 */
#define INFINITY_CHARGING_SET_AUTO_RESUME	_IOW(INFINITY_CHARGING_MAGIC, 4, int)

/* Platform driver registration */
extern struct platform_driver infinity_charging_driver;

#endif /* __LINUX_INFINITY_CHARGING_CONTROL_H */