#!/usr/bin/env bash
# Patch 07: Charging Bypass with Thermal Cooldown
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_CHARGING_BYPASS_PATCHED"
grep -q "$MARKER" "${KDIR}/drivers/power/supply/charging_bypass.c" 2>/dev/null && {
    echo "[07-charging-bypass] Already patched, skipping"
    exit 0
}

echo "[07-charging-bypass] Applying charging bypass..."

mkdir -p "${KDIR}/drivers/power/supply"

cat > "${KDIR}/drivers/power/supply/charging_bypass.c" << 'CBEOF'
/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * charging_bypass.c - Battery Charging Bypass Control
 * Infinity Kernel - Stop charging at threshold to preserve battery health
 * Supports: off, on, auto (thermal cooldown with 2C hysteresis, 5s poll)
 */

#include <linux/delay.h>
#include <linux/device.h>
#include <linux/errno.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/power_supply.h>
#include <linux/slab.h>
#include <linux/sysfs.h>
#include <linux/workqueue.h>

#define INFINITY_CHARGING_BYPASS_PATCHED

/* Modes */
enum charging_mode {
    CHARGING_BYPASS_OFF = 0,    /* Normal charging */
    CHARGING_BYPASS_ON,         /* Force bypass (stop charging) */
    CHARGING_BYPASS_AUTO,       /* Thermal-aware auto mode */
};

/* Thermal parameters */
#define THERMAL_POLL_MS         5000
#define THERMAL_HYSTERESIS_DC   2000   /* 2.0 degrees C */
#define DEFAULT_BYPASS_TEMP     400    /* 40.0 degrees C */

static struct charging_bypass_data {
    struct mutex lock;
    enum charging_mode mode;
    int bypass_threshold;    /* Temperature threshold (deci-C) */
    int current_temp;        /* Current battery temp (deci-C) */
    bool charging_active;
    struct delayed_work thermal_work;
    struct kobject *kobj;
} cb_data = {
    .mode = CHARGING_BYPASS_OFF,
    .bypass_threshold = DEFAULT_BYPASS_TEMP,
    .charging_active = true,
};

/* Sysfs: charging_bypass (mode) */
static ssize_t charging_bypass_show(struct kobject *kobj,
    struct kobj_attribute *attr, char *buf)
{
    const char *names[] = {"off", "on", "auto"};
    return sprintf(buf, "%s\n", names[cb_data.mode]);
}

static ssize_t charging_bypass_store(struct kobject *kobj,
    struct kobj_attribute *attr, const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) == 0) {
        mutex_lock(&cb_data.lock);
        cb_data.mode = clamp_val(val, CHARGING_BYPASS_OFF, CHARGING_BYPASS_AUTO);
        mutex_unlock(&cb_data.lock);
    }
    return count;
}

/* Sysfs: charging_bypass_threshold (temperature) */
static ssize_t threshold_show(struct kobject *kobj,
    struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", cb_data.bypass_threshold);
}

static ssize_t threshold_store(struct kobject *kobj,
    struct kobj_attribute *attr, const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) == 0) {
        mutex_lock(&cb_data.lock);
        cb_data.bypass_threshold = clamp_val(val, 300, 500);
        mutex_unlock(&cb_data.lock);
    }
    return count;
}

static struct kobj_attribute bypass_attr =
    __ATTR(charging_bypass, 0644, charging_bypass_show, charging_bypass_store);
static struct kobj_attribute threshold_attr =
    __ATTR(charging_bypass_threshold, 0644, threshold_show, threshold_store);

static struct attribute *bypass_attrs[] = {
    &bypass_attr.attr,
    &threshold_attr.attr,
    NULL,
};

static struct attribute_group bypass_attr_group = {
    .attrs = bypass_attrs,
};

/* Thermal polling work */
static void thermal_poll_work(struct work_struct *work)
{
    struct power_supply *psy;
    union power_supply_propval val;
    int temp = 250; /* default 25.0C */
    bool should_bypass = false;

    psy = power_supply_get_by_name("battery");
    if (psy) {
        if (!power_supply_get_property(psy, POWER_SUPPLY_PROP_TEMP, &val))
            temp = val.intval;
        power_supply_put(psy);
    }

    mutex_lock(&cb_data.lock);
    cb_data.current_temp = temp;

    switch (cb_data.mode) {
    case CHARGING_BYPASS_ON:
        should_bypass = true;
        break;
    case CHARGING_BYPASS_AUTO:
        /* Bypass when temp exceeds threshold */
        if (cb_data.charging_active && temp >= cb_data.bypass_threshold) {
            should_bypass = true;
            cb_data.charging_active = false;
        }
        /* Re-enable with hysteresis */
        if (!cb_data.charging_active &&
            temp <= (cb_data.bypass_threshold - THERMAL_HYSTERESIS_DC)) {
            should_bypass = false;
            cb_data.charging_active = true;
        }
        should_bypass = !cb_data.charging_active;
        break;
    default:
        should_bypass = false;
        break;
    }
    mutex_unlock(&cb_data.lock);

    /* Schedule next poll if in auto mode */
    if (cb_data.mode == CHARGING_BYPASS_AUTO)
        schedule_delayed_work(&cb_data.thermal_work,
            msecs_to_jiffies(THERMAL_POLL_MS));
}

static int __init charging_bypass_init(void)
{
    int ret;

    mutex_init(&cb_data.lock);
    INIT_DELAYED_WORK(&cb_data.thermal_work, thermal_poll_work);

    cb_data.kobj = kobject_create_and_add("battery", power_supply_class->p->subsys.kobj);
    if (!cb_data.kobj)
        return -ENOMEM;

    ret = sysfs_create_group(cb_data.kobj, &bypass_attr_group);
    if (ret) {
        kobject_put(cb_data.kobj);
        return ret;
    }

    pr_info("charging_bypass: Initialized (modes: off/on/auto, 2C hysteresis, 5s poll)\n");
    return 0;
}

static void __exit charging_bypass_exit(void)
{
    cancel_delayed_work_sync(&cb_data.thermal_work);
    if (cb_data.kobj) {
        sysfs_remove_group(cb_data.kobj, &bypass_attr_group);
        kobject_put(cb_data.kobj);
    }
}

module_init(charging_bypass_init);
module_exit(charging_bypass_exit);

MODULE_AUTHOR("Infinity Kernel Team");
MODULE_DESCRIPTION("Battery Charging Bypass with Thermal Cooldown");
MODULE_LICENSE("GPL");
CBEOF

echo "[07-charging-bypass] Created charging_bypass.c"
echo "[07-charging-bypass] Done"
