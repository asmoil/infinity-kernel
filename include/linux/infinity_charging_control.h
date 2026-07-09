/*
 * Infinity Kernel Charging Control
 * Poco X3 Pro (vayu/bhima) | SM8150
 *
 * SPDX-License-Identifier: GPL-2.0
 */

#ifndef _INFINITY_CHARGING_CONTROL_H
#define _INFINITY_CHARGING_CONTROL_H

#include <linux/types.h>

/* Charging control states */
#define CHARGING_CTRL_ENABLED  1
#define CHARGING_CTRL_DISABLED 0

/* Default charge current limits (mA) */
#define CHARGE_CURRENT_LIMIT_NONE   0
#define CHARGE_CURRENT_LIMIT_MIN    100
#define CHARGE_CURRENT_LIMIT_MAX    3000
#define CHARGE_CURRENT_LIMIT_STEP   100

/* Default charge voltage limits (mV) */
#define CHARGE_VOLTAGE_LIMIT_NONE   0
#define CHARGE_VOLTAGE_LIMIT_4350   4350
#define CHARGE_VOLTAGE_LIMIT_4200   4200
#define CHARGE_VOLTAGE_LIMIT_4000   4000

/* Charging control configuration */
struct infinity_charge_config {
    bool charging_enabled;
    unsigned int current_limit_ma;    /* 0 = no limit */
    unsigned int voltage_limit_mv;    /* 0 = no limit */
};

/* Sysfs attribute structure */
struct infinity_chg_attr {
    struct kobj_attribute kobj_attr;
    ssize_t (*show)(struct kobject *kobj, struct kobj_attribute *attr, char *buf);
    ssize_t (*store)(struct kobject *kobj, struct kobj_attribute *attr,
                     const char *buf, size_t count);
};

/* Public API */
#ifdef CONFIG_CHARGING_CONTROL
int infinity_charging_control_init(void);
void infinity_charging_control_exit(void);
int infinity_charging_set_enabled(bool enabled);
bool infinity_charging_get_enabled(void);
int infinity_charging_set_current_limit(unsigned int ma);
unsigned int infinity_charging_get_current_limit(void);
int infinity_charging_set_voltage_limit(unsigned int mv);
unsigned int infinity_charging_get_voltage_limit(void);
#else
static inline int infinity_charging_control_init(void) { return 0; }
static inline void infinity_charging_control_exit(void) {}
static inline int infinity_charging_set_enabled(bool e) { return 0; }
static inline bool infinity_charging_get_enabled(void) { return true; }
static inline int infinity_charging_set_current_limit(unsigned int m) { return 0; }
static inline unsigned int infinity_charging_get_current_limit(void) { return 0; }
static inline int infinity_charging_set_voltage_limit(unsigned int m) { return 0; }
static inline unsigned int infinity_charging_get_voltage_limit(void) { return 0; }
#endif

#endif /* _INFINITY_CHARGING_CONTROL_H */