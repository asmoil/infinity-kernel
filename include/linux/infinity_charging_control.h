/*
 * Infinity Charging Bypass Control Driver
 * Public API Header
 *
 * Copyright (c) 2024 Infinity Kernel Project
 * Author: Infinity Kernel Team
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * Target: Linux 4.14.180 | Device: Poco X3 Pro (vayu/bhima)
 * SoC: Qualcomm Snapdragon 732G (SM7150-AC)
 */

#ifndef _LINUX_INFINITY_CHARGING_CONTROL_H
#define _LINUX_INFINITY_CHARGING_CONTROL_H

#include <linux/types.h>
#include <linux/ioctl.h>

/* ------------------------------------------------------------------ */
/*  Charging Modes                                                     */
/* ------------------------------------------------------------------ */
enum charging_mode {
	CHARGING_MODE_DISABLED  = 0,  /* Bypass disabled, stock charging   */
	CHARGING_MODE_LIGHT     = 1,  /* Light gaming    - 2500mA limit    */
	CHARGING_MODE_BALANCED  = 2,  /* Balanced gaming - 2000mA limit    */
	CHARGING_MODE_EXTREME   = 3,  /* Extreme gaming  - 1500mA limit    */
	CHARGING_MODE_ULTRA     = 4,  /* Ultra gaming    -  500mA limit    */
	CHARGING_MODE_MAX       = 5,  /* Sentinel, do not use              */
};

/* ------------------------------------------------------------------ */
/*  IOCTL Magic & Commands                                             */
/* ------------------------------------------------------------------ */
#define INFINITY_CHARGE_IOC_MAGIC  'IC'

/* Get current charging mode */
#define IOC_CHARGE_GET_MODE \
	_IOR(INFINITY_CHARGE_IOC_MAGIC, 1, int)

/* Set charging mode (arg: enum charging_mode) */
#define IOC_CHARGE_SET_MODE \
	_IOW(INFINITY_CHARGE_IOC_MAGIC, 2, int)

/* Enable / disable charging bypass (arg: int 0|1) */
#define IOC_CHARGE_SET_ENABLED \
	_IOW(INFINITY_CHARGE_IOC_MAGIC, 3, int)

/* Query whether bypass is enabled (arg: int *) */
#define IOC_CHARGE_GET_ENABLED \
	_IOR(INFINITY_CHARGE_IOC_MAGIC, 4, int)

/* Get human-readable status string into user buffer */
#define IOC_CHARGE_GET_STATUS \
	_IOR(INFINITY_CHARGE_IOC_MAGIC, 5, char[128])

/* Get current battery temperature in millidegrees C */
#define IOC_CHARGE_GET_BATT_TEMP \
	_IOR(INFINITY_CHARGE_IOC_MAGIC, 6, int)

/* Get current battery capacity (percentage 0-100) */
#define IOC_CHARGE_GET_BATT_CAPACITY \
	_IOR(INFINITY_CHARGE_IOC_MAGIC, 7, int)

/* ------------------------------------------------------------------ */
/*  Device Information Struct (exposed via sysfs / ioctl)              */
/* ------------------------------------------------------------------ */
struct infinity_charge_info {
	int mode;           /* Current enum charging_mode        */
	int enabled;        /* 1 = bypass active, 0 = stock      */
	int battery_temp;   /* Battery temp in millidegrees C    */
	int battery_cap;    /* Battery capacity 0-100 %          */
	int current_limit;  /* Active charge current limit (mA)  */
	int thermal_state;  /* 0 = normal, 1 = cooldown          */
};

/* ------------------------------------------------------------------ */
/*  Thermal Thresholds (defaults, overridable via DT)                  */
/* ------------------------------------------------------------------ */
#define CHARGE_COOLDOWN_TEMP   45000   /* 45 °C  - enter cooldown */
#define CHARGE_RESUME_TEMP     40000   /* 40 °C  - exit cooldown  */
#define CHARGE_LOW_BATT_CAP    15      /* 15 %   - auto-resume    */

/* ------------------------------------------------------------------ */
/*  Charge Current Limits per Mode (mA)                                */
/* ------------------------------------------------------------------ */
#define CHARGE_CURRENT_LIGHT     2500
#define CHARGE_CURRENT_BALANCED  2000
#define CHARGE_CURRENT_EXTREME   1500
#define CHARGE_CURRENT_ULTRA      500

/* ------------------------------------------------------------------ */
/*  sysfs Attribute Constants                                          */
/* ------------------------------------------------------------------ */
#define SYSFS_DIR_NAME  "charging_control"

/* ------------------------------------------------------------------ */
/*  Kernel-internal helper (used by other kernel subsystems)          */
/* ------------------------------------------------------------------ */
#ifdef __KERNEL__

/**
 * infinity_charge_get_current_limit() - Return active mA limit.
 * Returns the configured limit when bypass is enabled and not in
 * thermal cooldown; otherwise returns 0 (no limit / stock).
 */
int infinity_charge_get_current_limit(void);

/**
 * infinity_charge_is_enabled() - Check if bypass is currently active.
 */
int infinity_charge_is_enabled(void);

/**
 * infinity_charge_get_mode() - Return current charging_mode enum value.
 */
int infinity_charge_get_mode(void);

#endif /* __KERNEL__ */

#endif /* _LINUX_INFINITY_CHARGING_CONTROL_H */