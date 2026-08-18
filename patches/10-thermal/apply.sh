#!/usr/bin/env bash
# Patch 10: Simple Thermal Sysfs Control
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_SIMPLE_THERMAL_PATCHED"
grep -q "$MARKER" "${KDIR}/drivers/thermal/simple_thermal.c" 2>/dev/null && {
    echo "[10-thermal] Already patched, skipping"
    exit 0
}

echo "[10-thermal] Applying simple thermal sysfs..."

mkdir -p "${KDIR}/drivers/thermal"

cat > "${KDIR}/drivers/thermal/simple_thermal.c" << 'THEOF'
/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * simple_thermal.c - Per-zone user_space governor sysfs
 * Infinity Kernel - Override thermal zone governor to user_space
 */

#include <linux/err.h>
#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/module.h>
#include <linux/thermal.h>
#include <linux/slab.h>

#define INFINITY_SIMPLE_THERMAL_PATCHED

struct thermal_zone_ctrl {
    struct thermal_zone_device *tz;
    struct kobject *kobj;
    struct attribute_group attr_group;
    struct kobj_attribute governor_attr;
    struct kobj_attribute temp_attr;
    struct kobj_attribute trip_attr;
    char governor_name[THERMAL_NAME_LENGTH];
};

static struct thermal_zone_ctrl **zone_ctrls;
static int zone_count;
static struct kobject *simple_thermal_kobj;

static ssize_t governor_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    struct thermal_zone_ctrl *ctrl = container_of(attr, struct thermal_zone_ctrl, governor_attr);
    if (ctrl->tz)
        return sprintf(buf, "%s\n", ctrl->tz->governor->name);
    return sprintf(buf, "none\n");
}

static ssize_t governor_store(struct kobject *kobj, struct kobj_attribute *attr,
                              const char *buf, size_t count)
{
    struct thermal_zone_ctrl *ctrl = container_of(attr, struct thermal_zone_ctrl, governor_attr);
    char name[THERMAL_NAME_LENGTH];
    int ret;

    if (count >= THERMAL_NAME_LENGTH)
        return -EINVAL;

    strlcpy(name, buf, count);
    if (name[count - 1] == '\n')
        name[count - 1] = '\0';

    if (ctrl->tz) {
        struct thermal_governor *gov;

        get_thermal_governor(name, &gov);
        if (gov) {
            ret = thermal_zone_set_governor(ctrl->tz, gov);
            if (ret == 0)
                strlcpy(ctrl->governor_name, name, THERMAL_NAME_LENGTH);
        }
    }
    return count;
}

static ssize_t temp_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    struct thermal_zone_ctrl *ctrl = container_of(attr, struct thermal_zone_ctrl, temp_attr);
    int temp = 0;
    if (ctrl->tz)
        thermal_zone_get_temp(ctrl->tz, &temp);
    return sprintf(buf, "%d\n", temp);
}

static ssize_t trip_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    struct thermal_zone_ctrl *ctrl = container_of(attr, struct thermal_zone_ctrl, trip_attr);
    if (ctrl->tz && ctrl->tz->trips > 0)
        return sprintf(buf, "%d\n", ctrl->tz->trips[0].temperature);
    return sprintf(buf, "0\n");
}

static int __init simple_thermal_init(void)
{
    struct thermal_zone_device *tz;
    int i = 0, ret;

    /* Count thermal zones */
    for_each_thermal_zone(tz)
        i++;
    if (i == 0)
        return -ENODEV;

    zone_count = i;
    zone_ctrls = kcalloc(zone_count, sizeof(*zone_ctrls), GFP_KERNEL);
    if (!zone_ctrls)
        return -ENOMEM;

    simple_thermal_kobj = kobject_create_and_add("simple_thermal", kernel_kobj);
    if (!simple_thermal_kobj) {
        kfree(zone_ctrls);
        return -ENOMEM;
    }

    i = 0;
    for_each_thermal_zone(tz) {
        struct thermal_zone_ctrl *ctrl;
        struct attribute **attrs;
        char name[32];

        ctrl = kzalloc(sizeof(*ctrl), GFP_KERNEL);
        if (!ctrl)
            continue;

        ctrl->tz = tz;
        snprintf(ctrl->governor_name, THERMAL_NAME_LENGTH, "%s", tz->governor->name);

        snprintf(name, sizeof(name), "%s", tz->type);
        ctrl->kobj = kobject_create_and_add(name, simple_thermal_kobj);
        if (!ctrl->kobj) {
            kfree(ctrl);
            continue;
        }

        attrs = kzalloc(4 * sizeof(struct attribute *), GFP_KERNEL);
        if (!attrs) {
            kobject_put(ctrl->kobj);
            kfree(ctrl);
            continue;
        }

        sysfs_attr_init(&ctrl->governor_attr.attr);
        ctrl->governor_attr.attr.name = "governor";
        ctrl->governor_attr.attr.mode = 0644;
        ctrl->governor_attr.show = governor_show;
        ctrl->governor_attr.store = governor_store;
        attrs[0] = &ctrl->governor_attr.attr;

        sysfs_attr_init(&ctrl->temp_attr.attr);
        ctrl->temp_attr.attr.name = "temp";
        ctrl->temp_attr.attr.mode = 0444;
        ctrl->temp_attr.show = temp_show;
        attrs[1] = &ctrl->temp_attr.attr;

        sysfs_attr_init(&ctrl->trip_attr.attr);
        ctrl->trip_attr.attr.name = "trip_temp";
        ctrl->trip_attr.attr.mode = 0444;
        ctrl->trip_attr.show = trip_show;
        attrs[2] = &ctrl->trip_attr.attr;
        attrs[3] = NULL;

        ctrl->attr_group.attrs = attrs;
        ret = sysfs_create_group(ctrl->kobj, &ctrl->attr_group);
        if (ret) {
            kobject_put(ctrl->kobj);
            kfree(attrs);
            kfree(ctrl);
            continue;
        }

        zone_ctrls[i++] = ctrl;
    }

    pr_info("simple_thermal: %d zones registered under /sys/kernel/simple_thermal/\n", i);
    return 0;
}

static void __exit simple_thermal_exit(void)
{
    int i;
    for (i = 0; i < zone_count; i++) {
        if (!zone_ctrls[i])
            continue;
        sysfs_remove_group(zone_ctrls[i]->kobj, &zone_ctrls[i]->attr_group);
        kobject_put(zone_ctrls[i]->kobj);
        kfree(zone_ctrls[i]->attr_group.attrs);
        kfree(zone_ctrls[i]);
    }
    kfree(zone_ctrls);
    kobject_put(simple_thermal_kobj);
}

module_init(simple_thermal_init);
module_exit(simple_thermal_exit);

MODULE_AUTHOR("Infinity Kernel Team");
MODULE_DESCRIPTION("Per-zone Thermal Governor Sysfs Control");
MODULE_LICENSE("GPL");
THEOF

echo "[10-thermal] Created simple_thermal.c"
echo "[10-thermal] Done"
