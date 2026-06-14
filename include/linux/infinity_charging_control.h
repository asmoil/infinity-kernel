/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Infinity Kernel Charging Control Header
 * Copyright (c) 2024 Infinity Kernel Team
 * For Poco X3 Pro (vayu/bhima) SM8250-AC
 */

#ifndef _INFINITY_CHARGING_CONTROL_H
#define _INFINITY_CHARGING_CONTROL_H

#include <linux/types.h>
#include <linux/ioctl.h>

/* Charging modes */
enum charging_mode {
	CHARGING_MODE_NORMAL		= 0,
	CHARGING_MODE_BALANCE		= 1,
	CHARGING_MODE_PERFORMANCE	= 2,
	CHARGING_MODE_GAME		= 3,
	CHARGING_MODE_BYPASS		= 4,
	CHARGING_MODE_CUSTOM		= 5,
	_CHARGING_MODE_MAX
};

/* Charging states */
enum charging_state {
	CHARGING_STATE_DISCHARGING	= 0,
	CHARGING_STATE_CHARGING		= 1,
	CHARGING_STATE_FULL		= 2,
	_CHARGING_STATE_MAX
};

/* IOCTL commands */
#define INFINITY_CHARGE_IOC_MAGIC	'IC'

#define INFINITY_CHARGE_GET_MODE	_IOR(INFINITY_CHARGE_IOC_MAGIC, 1, int)
#define INFINITY_CHARGE_SET_MODE	_IOW(INFINITY_CHARGE_IOC_MAGIC, 2, int)
#define INFINITY_CHARGE_GET_STATE	_IOR(INFINITY_CHARGE_IOC_MAGIC, 3, int)
#define INFINITY_CHARGE_GET_TEMP	_IOR(INFINITY_CHARGE_IOC_MAGIC, 4, int)
#define INFINITY_CHARGE_GET_VOLTAGE	_IOR(INFINITY_CHARGE_IOC_MAGIC, 5, int)
#define INFINITY_CHARGE_GET_CURRENT	_IOR(INFINITY_CHARGE_IOC_MAGIC, 6, int)
#define INFINITY_CHARGE_SET_CUSTOM_LIMIT	_IOW(INFINITY_CHARGE_IOC_MAGIC, 7, int)

/* Charging config structure */
struct infinity_charging_config {
	int mode;
	int temp_limit;		/* Celsius, 0 = default */
	int charge_limit_ma;	/* mA, 0 = no limit */
	int discharge_below;	/* mV, 0 = disabled */
};

/* System control */
#ifdef CONFIG_CHARGING_CONTROL
int infinity_charging_set_mode(enum charging_mode mode);
enum charging_mode infinity_charging_get_mode(void);
int infinity_charging_init(void);
void infinity_charging_exit(void);
#endif

#endif /* _INFINITY_CHARGING_CONTROL_H */