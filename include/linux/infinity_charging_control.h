/*
 * Infinity Charging Control
 * Copyright (c) 2024 Infinity Kernel Team
 * SPDX-License-Identifier: MIT
 *
 * Charging control driver for SM8150 (Poco X3 Pro vayu/bhima)
 * Supports 5 charging modes via sysfs and IOCTL
 */

#ifndef _INFINITY_CHARGING_CONTROL_H
#define _INFINITY_CHARGING_CONTROL_H

#include <linux/types.h>
#include <linux/ioctl.h>

/* Charging control modes */
#define CHARGING_CTRL_OFF       0   /* Charging disabled (bypass) */
#define CHARGING_CTRL_ON        1   /* Normal charging (default) */
#define CHARGING_CTRL_PAUSE     2   /* Pause at current level */
#define CHARGING_CTRL_LIMIT     3   /* Limit to threshold % */
#define CHARGING_CTRL_BYPASS    4   /* Bypass charging (direct power) */

/* IOCTL magic and commands */
#define INFINITY_CHARGE_IOC_MAGIC  'C'

#define INFINITY_CHARGE_GET_MODE  _IOR(INFINITY_CHARGE_IOC_MAGIC, 1, int)
#define INFINITY_CHARGE_SET_MODE  _IOW(INFINITY_CHARGE_IOC_MAGIC, 2, int)
#define INFINITY_CHARGE_GET_LEVEL _IOR(INFINITY_CHARGE_IOC_MAGIC, 3, int)
#define INFINITY_CHARGE_SET_LIMIT _IOW(INFINITY_CHARGE_IOC_MAGIC, 4, int)

/* Sysfs attributes */
#define CHARGE_CTRL_ENABLE_ATTR   "charge_ctrl_enable"
#define CHARGE_CTRL_MODE_ATTR     "charge_ctrl_mode"
#define CHARGE_CTRL_LIMIT_ATTR    "charge_ctrl_limit"

/* Callback type for platform-specific ops */
struct infinity_charge_ops {
    int (*get_mode)(void);
    int (*set_mode)(int mode);
    int (*get_level)(void);
    int (*set_limit)(int percent);
};

#endif /* _INFINITY_CHARGING_CONTROL_H */
