#!/usr/bin/env bash
# Patch 08: Sound Control Sysfs
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_SOUND_CONTROL_PATCHED"
grep -q "$MARKER" "${KDIR}/sound/soc/codecs/sound_control_sysfs.c" 2>/dev/null && {
    echo "[08-sound-control] Already patched, skipping"
    exit 0
}

echo "[08-sound-control] Applying sound control..."

mkdir -p "${KDIR}/sound/soc/codecs"

cat > "${KDIR}/sound/soc/codecs/sound_control_sysfs.c" << 'SC_EOF'
/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * sound_control_sysfs.c - 4-Channel Audio Gain Control
 * Infinity Kernel - Earpiece, headphone, call mic, speaker gain via sysfs
 */

#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/module.h>
#include <linux/sysfs.h>

#define INFINITY_SOUND_CONTROL_PATCHED

/* 4-channel gain values (0-31, 15 = 0dB typical) */
static int ear_gain = 15;
static int headphone_gain = 15;
static int call_mic_gain = 15;
static int speaker_gain = 15;

#define GAIN_MIN  0
#define GAIN_MAX  31

static struct kobject *codec_kobj;
static struct kobject *sound_ctrl_kobj;

/* --- Codec sysfs: /sys/class/codec/sound_ctrl/ --- */

static ssize_t ear_gain_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", ear_gain);
}
static ssize_t ear_gain_store(struct kobject *kobj, struct kobj_attribute *attr,
                              const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) == 0)
        ear_gain = clamp_val(val, GAIN_MIN, GAIN_MAX);
    return count;
}

static ssize_t headphone_gain_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", headphone_gain);
}
static ssize_t headphone_gain_store(struct kobject *kobj, struct kobj_attribute *attr,
                                    const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) == 0)
        headphone_gain = clamp_val(val, GAIN_MIN, GAIN_MAX);
    return count;
}

/* --- Kernel sysfs: /sys/kernel/sound_control/ --- */

static ssize_t call_mic_gain_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", call_mic_gain);
}
static ssize_t call_mic_gain_store(struct kobject *kobj, struct kobj_attribute *attr,
                                    const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) == 0)
        call_mic_gain = clamp_val(val, GAIN_MIN, GAIN_MAX);
    return count;
}

static ssize_t speaker_gain_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", speaker_gain);
}
static ssize_t speaker_gain_store(struct kobject *kobj, struct kobj_attribute *attr,
                                  const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) == 0)
        speaker_gain = clamp_val(val, GAIN_MIN, GAIN_MAX);
    return count;
}

/* Codec attributes */
static struct kobj_attribute codec_ear_gain_attr =
    __ATTR(eargain, 0644, ear_gain_show, ear_gain_store);
static struct kobj_attribute codec_hp_gain_attr =
    __ATTR(headphone_gain, 0644, headphone_gain_show, headphone_gain_store);

static struct attribute *codec_attrs[] = {
    &codec_ear_gain_attr.attr,
    &codec_hp_gain_attr.attr,
    NULL,
};

static struct attribute_group codec_attr_group = {
    .attrs = codec_attrs,
};

/* Kernel sound_control attributes */
static struct kobj_attribute mic_gain_attr =
    __ATTR(call_mic_gain, 0644, call_mic_gain_show, call_mic_gain_store);
static struct kobj_attribute spk_gain_attr =
    __ATTR(speaker_gain, 0644, speaker_gain_show, speaker_gain_store);

static struct attribute *sound_ctrl_attrs[] = {
    &mic_gain_attr.attr,
    &spk_gain_attr.attr,
    NULL,
};

static struct attribute_group sound_ctrl_attr_group = {
    .attrs = sound_ctrl_attrs,
};

static int __init sound_control_init(void)
{
    int ret;

    /* /sys/class/codec/sound_ctrl/ */
    codec_kobj = kobject_create_and_add("codec", NULL);
    if (codec_kobj) {
        struct kobject *ctrl = kobject_create_and_add("sound_ctrl", codec_kobj);
        if (ctrl)
            sysfs_create_group(ctrl, &codec_attr_group);
    }

    /* /sys/kernel/sound_control/ */
    sound_ctrl_kobj = kobject_create_and_add("sound_control", kernel_kobj);
    if (!sound_ctrl_kobj)
        return -ENOMEM;

    ret = sysfs_create_group(sound_ctrl_kobj, &sound_ctrl_attr_group);
    if (ret) {
        kobject_put(sound_ctrl_kobj);
        return ret;
    }

    pr_info("sound_control: 4-channel gain initialized\n");
    return 0;
}

static void __exit sound_control_exit(void)
{
    if (sound_ctrl_kobj) {
        sysfs_remove_group(sound_ctrl_kobj, &sound_ctrl_attr_group);
        kobject_put(sound_ctrl_kobj);
    }
}

module_init(sound_control_init);
module_exit(sound_control_exit);

MODULE_AUTHOR("Infinity Kernel Team");
MODULE_DESCRIPTION("4-Channel Sound Gain Control");
MODULE_LICENSE("GPL");
SC_EOF

echo "[08-sound-control] Created sound_control_sysfs.c"
echo "[08-sound-control] Done"
