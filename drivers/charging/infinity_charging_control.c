/*
 * Infinity Charging Control Driver
 * Poco X3 Pro (vayu/bhima) | SM8150/SM8250
 *
 * Charging bypass with 5 gaming modes, thermal monitoring,
 * SoC-based pause/resume, and sysfs interface.
 *
 * Copyright (c) 2024 Infinity Kernel Project
 * License: GPL-2.0
 */

#include <linux/module.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/power_supply.h>
#include <linux/thermal.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/workqueue.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/of.h>
#include <linux/io.h>
#include <linux/infinity_charging_control.h>

#define DRIVER_NAME "infinity_charging"
#define MONITOR_INTERVAL_MS 2000
#define THERMAL_HYSTERESIS 5
#define SOC_HYSTERESIS 2

struct mode_config {
        int pause_soc;
        int thermal_limit;
        int current_reduction;
};

static const struct mode_config mode_table[] = {
        [CHARGING_MODE_OFF]      = { 0,  0,   0 },
        [CHARGING_MODE_LIGHT]    = { 80, 45,  200 },
        [CHARGING_MODE_BALANCED] = { 70, 42,  400 },
        [CHARGING_MODE_EXTREME]  = { 60, 40,  600 },
        [CHARGING_MODE_ULTRA]    = { 50, 38,  800 },
};

struct infinity_charging_data {
        struct device *dev;
        struct power_supply *batt_psy;
        struct delayed_work monitor_work;
        struct kobject *kobj;

        enum infinity_charging_mode current_mode;
        int thermal_limit_override;
        int auto_resume_threshold;
        int is_charging;
        int thermal_throttled;
        int bypass_active;
        int battery_temp;
        int battery_level;
        int battery_voltage;
        int battery_current;
};

static struct infinity_charging_data *g_data;

static int get_battery_capacity(struct infinity_charging_data *data)
{
        union power_supply_propval val = { 0 };
        int ret;

        if (!data->batt_psy)
                return -ENODEV;

        ret = power_supply_get_property(data->batt_psy, POWER_SUPPLY_PROP_CAPACITY, &val);
        if (ret)
                return ret;
        return val.intval;
}

static int get_battery_temp(struct infinity_charging_data *data)
{
        union power_supply_propval val = { 0 };
        int ret;

        if (!data->batt_psy)
                return -ENODEV;

        ret = power_supply_get_property(data->batt_psy, POWER_SUPPLY_PROP_TEMP, &val);
        if (ret)
                return ret;
        return val.intval;
}

static int get_battery_voltage(struct infinity_charging_data *data)
{
        union power_supply_propval val = { 0 };
        int ret;

        if (!data->batt_psy)
                return -ENODEV;

        ret = power_supply_get_property(data->batt_psy, POWER_SUPPLY_PROP_VOLTAGE_NOW, &val);
        if (ret)
                return ret;
        return val.intval;
}

static int get_battery_current(struct infinity_charging_data *data)
{
        union power_supply_propval val = { 0 };
        int ret;

        if (!data->batt_psy)
                return -ENODEV;

        ret = power_supply_get_property(data->batt_psy, POWER_SUPPLY_PROP_CURRENT_NOW, &val);
        if (ret)
                return ret;
        return val.intval;
}

static int set_charging_enable(struct infinity_charging_data *data, bool enable)
{
        union power_supply_propval val = { 0 };
        int ret;

        if (!data->batt_psy)
                return -ENODEV;

        val.intval = enable ? 1 : 0;
        ret = power_supply_set_property(data->batt_psy,
                        POWER_SUPPLY_PROP_CHARGE_ENABLED, &val);
        if (!ret)
                data->is_charging = enable ? 1 : 0;

        return ret;
}

static void monitor_work_fn(struct work_struct *work)
{
        struct infinity_charging_data *data =
                container_of(work, struct infinity_charging_data, monitor_work.work);
        const struct mode_config *cfg;
        int temp, capacity, throttle_temp;

        if (data->current_mode == CHARGING_MODE_OFF) {
                if (!data->is_charging)
                        goto out;
                set_charging_enable(data, true);
                data->bypass_active = 0;
                goto out;
        }

        cfg = &mode_table[data->current_mode];
        temp = get_battery_temp(data);
        capacity = get_battery_capacity(data);
        data->battery_temp = temp;
        data->battery_level = capacity;
        data->battery_voltage = get_battery_voltage(data);
        data->battery_current = get_battery_current(data);

        throttle_temp = data->thermal_limit_override > 0
                        ? data->thermal_limit_override
                        : cfg->thermal_limit;

        if (temp >= throttle_temp * 10) {
                if (!data->thermal_throttled) {
                        data->thermal_throttled = 1;
                        pr_info("%s: thermal throttle at %d.%dC (limit %dC)\n",
                                DRIVER_NAME, temp / 10, temp % 10, throttle_temp);
                }
                if (data->is_charging) {
                        set_charging_enable(data, false);
                        data->bypass_active = 1;
                }
        } else if (data->thermal_throttled &&
                   temp <= (throttle_temp - THERMAL_HYSTERESIS) * 10) {
                data->thermal_throttled = 0;
                pr_info("%s: thermal resume at %d.%dC\n",
                        DRIVER_NAME, temp / 10, temp % 10);
        }

        if (capacity >= cfg->pause_soc) {
                if (data->is_charging) {
                        set_charging_enable(data, false);
                        data->bypass_active = 1;
                        pr_info("%s: SOC pause at %d%% (mode=%d)\n",
                                DRIVER_NAME, capacity, data->current_mode);
                }
        } else if (data->bypass_active && !data->thermal_throttled &&
                   capacity <= (cfg->pause_soc - SOC_HYSTERESIS)) {
                set_charging_enable(data, true);
                data->bypass_active = 0;
                pr_info("%s: SOC resume at %d%% (threshold=%d%%)\n",
                        DRIVER_NAME, capacity, cfg->pause_soc - SOC_HYSTERESIS);
        }

out:
        schedule_delayed_work(&data->monitor_work,
                        msecs_to_jiffies(MONITOR_INTERVAL_MS));
}

static ssize_t charging_mode_show(struct kobject *kobj,
                struct kobj_attribute *attr, char *buf)
{
        if (!g_data)
                return -ENODEV;
        return sprintf(buf, "%d\n", g_data->current_mode);
}

static ssize_t charging_mode_store(struct kobject *kobj,
                struct kobj_attribute *attr, const char *buf, size_t count)
{
        int mode;
        if (!g_data)
                return -ENODEV;
        if (kstrtoint(buf, 10, &mode))
                return -EINVAL;
        if (mode < 0 || mode > CHARGING_MODE_ULTRA)
                return -EINVAL;
        g_data->current_mode = mode;
        pr_info("%s: mode set to %d\n", DRIVER_NAME, mode);
        return count;
}

static ssize_t status_show(struct kobject *kobj,
                struct kobj_attribute *attr, char *buf)
{
        if (!g_data)
                return -ENODEV;
        return sprintf(buf,
                "mode=%d charging=%d bypass=%d thermal=%d temp=%d level=%d\n",
                g_data->current_mode, g_data->is_charging,
                g_data->bypass_active, g_data->thermal_throttled,
                g_data->battery_temp, g_data->battery_level);
}

static ssize_t battery_temp_show(struct kobject *kobj,
                struct kobj_attribute *attr, char *buf)
{
        if (!g_data)
                return -ENODEV;
        return sprintf(buf, "%d.%d\n",
                g_data->battery_temp / 10, g_data->battery_temp % 10);
}

static ssize_t battery_level_show(struct kobject *kobj,
                struct kobj_attribute *attr, char *buf)
{
        if (!g_data)
                return -ENODEV;
        return sprintf(buf, "%d\n", g_data->battery_level);
}

static struct kobj_attribute mode_attr =
        __ATTR(charging_mode, 0644, charging_mode_show, charging_mode_store);
static struct kobj_attribute status_attr =
        __ATTR(status, 0444, status_show, NULL);
static struct kobj_attribute temp_attr =
        __ATTR(battery_temp, 0444, battery_temp_show, NULL);
static struct kobj_attribute level_attr =
        __ATTR(battery_level, 0444, battery_level_show, NULL);

static struct attribute *charging_attrs[] = {
        &mode_attr.attr,
        &status_attr.attr,
        &temp_attr.attr,
        &level_attr.attr,
        NULL,
};

static struct attribute_group charging_attr_group = {
        .attrs = charging_attrs,
};

static long infinity_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
        struct infinity_charging_status status;
        void __user *uarg = (void __user *)arg;
        int mode;

        if (!g_data)
                return -ENODEV;

        switch (cmd) {
        case INFINITY_CHARGING_SET_MODE:
                if (copy_from_user(&mode, uarg, sizeof(mode)))
                        return -EFAULT;
                if (mode < 0 || mode > CHARGING_MODE_ULTRA)
                        return -EINVAL;
                g_data->current_mode = mode;
                return 0;

        case INFINITY_CHARGING_GET_STATUS:
                status.mode = g_data->current_mode;
                status.battery_temp = g_data->battery_temp;
                status.battery_current = g_data->battery_current;
                status.battery_voltage = g_data->battery_voltage;
                status.is_charging = g_data->is_charging;
                status.thermal_throttled = g_data->thermal_throttled;
                status.bypass_active = g_data->bypass_active;
                if (copy_to_user(uarg, &status, sizeof(status)))
                        return -EFAULT;
                return 0;

        case INFINITY_CHARGING_SET_THERMAL_LIMIT:
                if (copy_from_user(&mode, uarg, sizeof(mode)))
                        return -EFAULT;
                if (mode < 0 || mode > 50)
                        return -EINVAL;
                g_data->thermal_limit_override = mode;
                return 0;

        case INFINITY_CHARGING_SET_AUTO_RESUME:
                if (copy_from_user(&mode, uarg, sizeof(mode)))
                        return -EFAULT;
                g_data->auto_resume_threshold = mode;
                return 0;

        default:
                return -ENOTTY;
        }
}

static const struct file_operations infinity_fops = {
        .owner = THIS_MODULE,
        .unlocked_ioctl = infinity_ioctl,
        .compat_ioctl = infinity_ioctl,
};

static struct miscdevice infinity_misc = {
        .minor = MISC_DYNAMIC_MINOR,
        .name = "infinity_charging_control",
        .fops = &infinity_fops,
};

static int infinity_charging_probe(struct platform_device *pdev)
{
        struct infinity_charging_data *data;
        int ret;

        data = devm_kzalloc(&pdev->dev, sizeof(*data), GFP_KERNEL);
        if (!data)
                return -ENOMEM;

        data->dev = &pdev->dev;
        data->current_mode = CHARGING_MODE_OFF;
        data->thermal_limit_override = 0;
        data->auto_resume_threshold = 15;
        data->is_charging = 1;
        data->bypass_active = 0;

        data->batt_psy = power_supply_get_by_name("battery");
        if (!data->batt_psy)
                dev_warn(&pdev->dev, "battery power supply not found\n");

        INIT_DELAYED_WORK(&data->monitor_work, monitor_work_fn);

        data->kobj = kobject_create_and_add("infinity_charging", kernel_kobj);
        if (!data->kobj) {
                dev_err(&pdev->dev, "failed to create sysfs kobject\n");
                return -ENOMEM;
        }

        ret = sysfs_create_group(data->kobj, &charging_attr_group);
        if (ret) {
                dev_err(&pdev->dev, "failed to create sysfs group\n");
                kobject_put(data->kobj);
                return ret;
        }

        ret = misc_register(&infinity_misc);
        if (ret) {
                dev_err(&pdev->dev, "failed to register misc device\n");
                sysfs_remove_group(data->kobj, &charging_attr_group);
                kobject_put(data->kobj);
                return ret;
        }

        g_data = data;
        platform_set_drvdata(pdev, data);

        schedule_delayed_work(&data->monitor_work,
                        msecs_to_jiffies(MONITOR_INTERVAL_MS));

        dev_info(&pdev->dev, "Infinity Charging Control loaded\n");
        return 0;
}

static int infinity_charging_remove(struct platform_device *pdev)
{
        struct infinity_charging_data *data = platform_get_drvdata(pdev);

        cancel_delayed_work_sync(&data->monitor_work);

        if (data->kobj) {
                sysfs_remove_group(data->kobj, &charging_attr_group);
                kobject_put(data->kobj);
        }

        misc_deregister(&infinity_misc);

        if (data->batt_psy)
                power_supply_put(data->batt_psy);

        g_data = NULL;
        return 0;
}

static const struct of_device_id infinity_charging_of_match[] = {
        { .compatible = "infinity,charging-control" },
        { .compatible = "qcom,sm8150-charging-ctrl" },
        { .compatible = "qcom,sm8250-charging-ctrl" },
        { },
};
MODULE_DEVICE_TABLE(of, infinity_charging_of_match);

static struct platform_driver infinity_charging_driver = {
        .probe = infinity_charging_probe,
        .remove = infinity_charging_remove,
        .driver = {
                .name = DRIVER_NAME,
                .of_match_table = infinity_charging_of_match,
        },
};

module_platform_driver(infinity_charging_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Infinity Kernel Project");
MODULE_DESCRIPTION("Charging bypass control for Poco X3 Pro");
MODULE_VERSION("1.0.48");