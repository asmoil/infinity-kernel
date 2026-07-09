/*
 * Infinity Kernel Charging Control Driver
 * Poco X3 Pro (vayu/bhima) | SM8150
 *
 * Provides sysfs interface at /sys/kernel/charging_control/
 * to control charging behavior:
 *   - charging_enabled (rw): enable/disable charging
 *   - charge_current_limit (rw): limit in mA (0 = no limit)
 *   - charge_voltage_limit (rw): limit in mV (0 = no limit)
 *
 * SPDX-License-Identifier: GPL-2.0
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/slab.h>
#include <linux/power_supply.h>
#include <linux/workqueue.h>
#include <linux/mutex.h>

#include <linux/infinity_charging_control.h>

#define DRIVER_NAME "infinity_charging_control"
#define CHG_KOBJ_NAME "charging_control"

/* ── Module state ─────────────────────────────────────────────── */
static struct kobject *chg_kobj;
static DEFINE_MUTEX(chg_state_lock);

static struct infinity_charge_config chg_cfg = {
    .charging_enabled  = true,
    .current_limit_ma  = CHARGE_CURRENT_LIMIT_NONE,
    .voltage_limit_mv  = CHARGE_VOLTAGE_LIMIT_NONE,
};

/* ── Delayed work for charging state enforcement ──────────────── */
static void chg_enforce_work_fn(struct work_struct *work);
static DECLARE_DELAYED_WORK(chg_enforce_work, chg_enforce_work_fn);
static const unsigned long CHG_ENFORCE_INTERVAL_MS = 2000;

/* ── Sysfs: charging_enabled ──────────────────────────────────── */
static ssize_t charging_enabled_show(struct kobject *kobj,
                                     struct kobj_attribute *attr, char *buf)
{
    bool enabled;
    mutex_lock(&chg_state_lock);
    enabled = chg_cfg.charging_enabled;
    mutex_unlock(&chg_state_lock);
    return snprintf(buf, PAGE_SIZE, "%d\n", enabled ? 1 : 0);
}

static ssize_t charging_enabled_store(struct kobject *kobj,
                                      struct kobj_attribute *attr,
                                      const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) != 0)
        return -EINVAL;

    mutex_lock(&chg_state_lock);
    chg_cfg.charging_enabled = (val != 0);
    mutex_unlock(&chg_state_lock);

    pr_info("%s: charging %s\n", DRIVER_NAME,
            chg_cfg.charging_enabled ? "enabled" : "disabled");

    /* Schedule enforcement */
    schedule_delayed_work(&chg_enforce_work,
                          msecs_to_jiffies(CHG_ENFORCE_INTERVAL_MS));
    return count;
}

static struct kobj_attribute charging_enabled_attr =
    __ATTR(charging_enabled, 0644, charging_enabled_show,
           charging_enabled_store);

/* ── Sysfs: charge_current_limit ──────────────────────────────── */
static ssize_t current_limit_show(struct kobject *kobj,
                                  struct kobj_attribute *attr, char *buf)
{
    unsigned int limit;
    mutex_lock(&chg_state_lock);
    limit = chg_cfg.current_limit_ma;
    mutex_unlock(&chg_state_lock);
    return snprintf(buf, PAGE_SIZE, "%u\n", limit);
}

static ssize_t current_limit_store(struct kobject *kobj,
                                   struct kobj_attribute *attr,
                                   const char *buf, size_t count)
{
    unsigned int val;
    if (kstrtouint(buf, 10, &val) != 0)
        return -EINVAL;

    if (val != CHARGE_CURRENT_LIMIT_NONE &&
        (val < CHARGE_CURRENT_LIMIT_MIN || val > CHARGE_CURRENT_LIMIT_MAX))
        return -EINVAL;

    mutex_lock(&chg_state_lock);
    chg_cfg.current_limit_ma = val;
    mutex_unlock(&chg_state_lock);

    pr_info("%s: current limit set to %u mA\n", DRIVER_NAME, val);
    schedule_delayed_work(&chg_enforce_work,
                          msecs_to_jiffies(CHG_ENFORCE_INTERVAL_MS));
    return count;
}

static struct kobj_attribute current_limit_attr =
    __ATTR(charge_current_limit, 0644, current_limit_show,
           current_limit_store);

/* ── Sysfs: charge_voltage_limit ──────────────────────────────── */
static ssize_t voltage_limit_show(struct kobject *kobj,
                                  struct kobj_attribute *attr, char *buf)
{
    unsigned int limit;
    mutex_lock(&chg_state_lock);
    limit = chg_cfg.voltage_limit_mv;
    mutex_unlock(&chg_state_lock);
    return snprintf(buf, PAGE_SIZE, "%u\n", limit);
}

static ssize_t voltage_limit_store(struct kobject *kobj,
                                   struct kobj_attribute *attr,
                                   const char *buf, size_t count)
{
    unsigned int val;
    if (kstrtouint(buf, 10, &val) != 0)
        return -EINVAL;

    if (val != CHARGE_VOLTAGE_LIMIT_NONE && val < CHARGE_VOLTAGE_LIMIT_4000)
        return -EINVAL;

    mutex_lock(&chg_state_lock);
    chg_cfg.voltage_limit_mv = val;
    mutex_unlock(&chg_state_lock);

    pr_info("%s: voltage limit set to %u mV\n", DRIVER_NAME, val);
    schedule_delayed_work(&chg_enforce_work,
                          msecs_to_jiffies(CHG_ENFORCE_INTERVAL_MS));
    return count;
}

static struct kobj_attribute voltage_limit_attr =
    __ATTR(charge_voltage_limit, 0644, voltage_limit_show,
           voltage_limit_store);

/* ── Charging enforcement worker ───────────────────────────────── */
static void chg_enforce_work_fn(struct work_struct *work)
{
    struct power_supply *batt_psy;
    union power_supply_propval val;
    int ret;

    mutex_lock(&chg_state_lock);

    batt_psy = power_supply_get_by_name("battery");
    if (!batt_psy) {
        pr_debug("%s: battery power_supply not found\n", DRIVER_NAME);
        goto out;
    }

    /* Enforce charging enabled/disabled via power supply */
    val.intval = chg_cfg.charging_enabled ? 1 : 0;
    ret = power_supply_set_property(batt_psy,
                                    POWER_SUPPLY_PROP_CHARGING_ENABLED,
                                    &val);
    if (ret && ret != -ENOSYS)
        pr_debug("%s: set charging_enabled failed: %d\n", DRIVER_NAME, ret);

    /* Enforce current limit if set */
    if (chg_cfg.current_limit_ma != CHARGE_CURRENT_LIMIT_NONE) {
        val.intval = chg_cfg.current_limit_ma * 1000; /* uA */
        ret = power_supply_set_property(batt_psy,
                                        POWER_SUPPLY_PROP_INPUT_CURRENT_LIMIT,
                                        &val);
        if (ret && ret != -ENOSYS)
            pr_debug("%s: set input_current_limit failed: %d\n",
                     DRIVER_NAME, ret);
    }

    /* Enforce voltage limit if set */
    if (chg_cfg.voltage_limit_mv != CHARGE_VOLTAGE_LIMIT_NONE) {
        val.intval = chg_cfg.voltage_limit_mv * 1000; /* uV */
        ret = power_supply_set_property(batt_psy,
                                        POWER_SUPPLY_PROP_VOLTAGE_MAX,
                                        &val);
        if (ret && ret != -ENOSYS)
            pr_debug("%s: set voltage_max failed: %d\n", DRIVER_NAME, ret);
    }

    power_supply_put(batt_psy);

out:
    mutex_unlock(&chg_state_lock);
}

/* ── Sysfs attributes array ───────────────────────────────────── */
static struct attribute *chg_attrs[] = {
    &charging_enabled_attr.attr,
    &current_limit_attr.attr,
    &voltage_limit_attr.attr,
    NULL,
};

static const struct attribute_group chg_attr_group = {
    .attrs = chg_attrs,
};

/* ── Module init/exit ─────────────────────────────────────────── */
int infinity_charging_control_init(void)
{
    int ret;

    chg_kobj = kobject_create_and_add(CHG_KOBJ_NAME, kernel_kobj);
    if (!chg_kobj) {
        pr_err("%s: failed to create kobject\n", DRIVER_NAME);
        return -ENOMEM;
    }

    ret = sysfs_create_group(chg_kobj, &chg_attr_group);
    if (ret) {
        pr_err("%s: failed to create sysfs group: %d\n", DRIVER_NAME, ret);
        kobject_put(chg_kobj);
        return ret;
    }

    /* Start enforcement worker */
    schedule_delayed_work(&chg_enforce_work,
                          msecs_to_jiffies(CHG_ENFORCE_INTERVAL_MS));

    pr_info("%s: initialized (enabled=%d, current_limit=%u mA, voltage_limit=%u mV)\n",
            DRIVER_NAME,
            chg_cfg.charging_enabled,
            chg_cfg.current_limit_ma,
            chg_cfg.voltage_limit_mv);
    return 0;
}

void infinity_charging_control_exit(void)
{
    cancel_delayed_work_sync(&chg_enforce_work);

    if (chg_kobj) {
        sysfs_remove_group(chg_kobj, &chg_attr_group);
        kobject_put(chg_kobj);
        chg_kobj = NULL;
    }

    pr_info("%s: unloaded\n", DRIVER_NAME);
}

/* ── Public API ───────────────────────────────────────────────── */
int infinity_charging_set_enabled(bool enabled)
{
    mutex_lock(&chg_state_lock);
    chg_cfg.charging_enabled = enabled;
    mutex_unlock(&chg_state_lock);
    schedule_delayed_work(&chg_enforce_work,
                          msecs_to_jiffies(CHG_ENFORCE_INTERVAL_MS));
    return 0;
}

bool infinity_charging_get_enabled(void)
{
    bool enabled;
    mutex_lock(&chg_state_lock);
    enabled = chg_cfg.charging_enabled;
    mutex_unlock(&chg_state_lock);
    return enabled;
}

int infinity_charging_set_current_limit(unsigned int ma)
{
    if (ma != CHARGE_CURRENT_LIMIT_NONE &&
        (ma < CHARGE_CURRENT_LIMIT_MIN || ma > CHARGE_CURRENT_LIMIT_MAX))
        return -EINVAL;
    mutex_lock(&chg_state_lock);
    chg_cfg.current_limit_ma = ma;
    mutex_unlock(&chg_state_lock);
    return 0;
}

unsigned int infinity_charging_get_current_limit(void)
{
    unsigned int limit;
    mutex_lock(&chg_state_lock);
    limit = chg_cfg.current_limit_ma;
    mutex_unlock(&chg_state_lock);
    return limit;
}

int infinity_charging_set_voltage_limit(unsigned int mv)
{
    if (mv != CHARGE_VOLTAGE_LIMIT_NONE && mv < CHARGE_VOLTAGE_LIMIT_4000)
        return -EINVAL;
    mutex_lock(&chg_state_lock);
    chg_cfg.voltage_limit_mv = mv;
    mutex_unlock(&chg_state_lock);
    return 0;
}

unsigned int infinity_charging_get_voltage_limit(void)
{
    unsigned int limit;
    mutex_lock(&chg_state_lock);
    limit = chg_cfg.voltage_limit_mv;
    mutex_unlock(&chg_state_lock);
    return limit;
}

module_init(infinity_charging_control_init);
module_exit(infinity_charging_control_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Infinity Kernel");
MODULE_DESCRIPTION("Charging Control Driver for Poco X3 Pro");
MODULE_VERSION("1.0");