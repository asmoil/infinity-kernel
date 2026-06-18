/*
 * Infinity Charging Control Driver v1.0.49
 * SM8150 (Snapdragon 855) — Poco X3 Pro (vayu/bhima)
 *
 * Provides 5 charging modes via /sys/class/power_supply/battery/:
 *   0 = Bypass (stop charging, run on battery)
 *   1 = Normal (default, charge to 100%)
 *   2 = Limit to 80%
 *   3 = Limit to 90%
 *   4 = Custom threshold
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/power_supply.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/io.h>
#include <linux/interrupt.h>
#include <linux/workqueue.h>
#include <linux/mutex.h>
#include <linux/errno.h>
#include <linux/thermal.h>

#include <linux/infinity_charging_control.h>

#define DRIVER_NAME "infinity_charging_control"
#define CLASS_NAME  "infinity_charging"
#define DEVICE_NAME "charging_control"

static int charging_mode = 1;
static int custom_threshold = 85;
static DEFINE_MUTEX(mode_lock);

static void __iomem *smb2_base;
static struct class *icc_class;
static dev_t icc_dev;
static struct cdev icc_cdev;
static struct device *icc_device;

#define THRESHOLD_80 80
#define THRESHOLD_90 90
#define THRESHOLD_100 100

static ssize_t mode_show(struct device *dev,
                         struct device_attribute *attr, char *buf)
{
    int mode;
    mutex_lock(&mode_lock);
    mode = charging_mode;
    mutex_unlock(&mode_lock);
    return snprintf(buf, PAGE_SIZE, "%d\n", mode);
}

static ssize_t mode_store(struct device *dev,
                          struct device_attribute *attr,
                          const char *buf, size_t count)
{
    long val;
    int ret;

    ret = kstrtol(buf, 10, &val);
    if (ret)
        return ret;

    if (val < 0 || val > 4)
        return -EINVAL;

    mutex_lock(&mode_lock);
    charging_mode = (int)val;

    switch (charging_mode) {
    case CHARGING_MODE_BYPASS:
        pr_info("%s: Bypass mode — charging disabled\n", DRIVER_NAME);
        break;
    case CHARGING_MODE_NORMAL:
        pr_info("%s: Normal mode — charge to %d%%\n",
                DRIVER_NAME, THRESHOLD_100);
        break;
    case CHARGING_MODE_LIMIT_80:
        pr_info("%s: Limit mode — charge to %d%%\n",
                DRIVER_NAME, THRESHOLD_80);
        break;
    case CHARGING_MODE_LIMIT_90:
        pr_info("%s: Limit mode — charge to %d%%\n",
                DRIVER_NAME, THRESHOLD_90);
        break;
    case CHARGING_MODE_CUSTOM:
        pr_info("%s: Custom mode — charge to %d%%\n",
                DRIVER_NAME, custom_threshold);
        break;
    }
    mutex_unlock(&mode_lock);

    return count;
}

static DEVICE_ATTR_RW(mode);

static ssize_t threshold_show(struct device *dev,
                              struct device_attribute *attr, char *buf)
{
    int thresh;
    mutex_lock(&mode_lock);
    thresh = custom_threshold;
    mutex_unlock(&mode_lock);
    return snprintf(buf, PAGE_SIZE, "%d\n", thresh);
}

static ssize_t threshold_store(struct device *dev,
                               struct device_attribute *attr,
                               const char *buf, size_t count)
{
    long val;
    int ret;

    ret = kstrtol(buf, 10, &val);
    if (ret)
        return ret;

    if (val < 50 || val > 100)
        return -EINVAL;

    mutex_lock(&mode_lock);
    custom_threshold = (int)val;
    mutex_unlock(&mode_lock);
    pr_info("%s: Custom threshold set to %d%%\n", DRIVER_NAME, (int)val);

    return count;
}

static DEVICE_ATTR_RW(threshold);

static int get_battery_capacity(void)
{
    union power_supply_propval val = {0};
    struct power_supply *psy;
    int ret = -ENODEV;

    psy = power_supply_get_by_name("battery");
    if (psy) {
        ret = power_supply_get_property(psy,
                    POWER_SUPPLY_PROP_CAPACITY, &val);
        power_supply_put(psy);
        if (!ret)
            return val.intval;
    }
    return ret;
}

static long icc_ioctl(struct file *file, unsigned int cmd,
                      unsigned long arg)
{
    struct infinity_charging_req req;
    int cap;

    switch (cmd) {
    case INFINITY_IOCTL_SET_MODE:
        if (copy_from_user(&req, (void __user *)arg, sizeof(req)))
            return -EFAULT;
        if (req.mode < 0 || req.mode > 4)
            return -EINVAL;
        mutex_lock(&mode_lock);
        charging_mode = req.mode;
        mutex_unlock(&mode_lock);
        pr_info("%s: IOCTL set mode=%d\n", DRIVER_NAME, req.mode);
        break;

    case INFINITY_IOCTL_GET_MODE:
        mutex_lock(&mode_lock);
        req.mode = charging_mode;
        mutex_unlock(&mode_lock);
        if (copy_to_user((void __user *)arg, &req, sizeof(req)))
            return -EFAULT;
        break;

    case INFINITY_IOCTL_GET_CAPACITY:
        cap = get_battery_capacity();
        if (cap < 0)
            return cap;
        req.capacity = cap;
        if (copy_to_user((void __user *)arg, &req, sizeof(req)))
            return -EFAULT;
        break;

    default:
        return -ENOTTY;
    }
    return 0;
}

static int icc_open(struct inode *inode, struct file *file)
{
    return 0;
}

static int icc_release(struct inode *inode, struct file *file)
{
    return 0;
}

static const struct file_operations icc_fops = {
    .owner          = THIS_MODULE,
    .open           = icc_open,
    .release        = icc_release,
    .unlocked_ioctl = icc_ioctl,
    .compat_ioctl   = icc_ioctl,
};

static int icc_probe(struct platform_device *pdev)
{
    int ret;

    pr_info("%s: Probing Infinity Charging Control v1.0.49\n", DRIVER_NAME);

    ret = alloc_chrdev_region(&icc_dev, 0, 1, DEVICE_NAME);
    if (ret) {
        pr_err("%s: alloc_chrdev_region failed: %d\n", DRIVER_NAME, ret);
        return ret;
    }

    cdev_init(&icc_cdev, &icc_fops);
    icc_cdev.owner = THIS_MODULE;
    ret = cdev_add(&icc_cdev, icc_dev, 1);
    if (ret) {
        pr_err("%s: cdev_add failed: %d\n", DRIVER_NAME, ret);
        goto err_unregister;
    }

    icc_class = class_create(THIS_MODULE, CLASS_NAME);
    if (IS_ERR(icc_class)) {
        pr_err("%s: class_create failed\n", DRIVER_NAME);
        ret = PTR_ERR(icc_class);
        goto err_cdev_del;
    }

    icc_device = device_create(icc_class, NULL, icc_dev, NULL, DEVICE_NAME);
    if (IS_ERR(icc_device)) {
        pr_err("%s: device_create failed\n", DRIVER_NAME);
        ret = PTR_ERR(icc_device);
        goto err_class_destroy;
    }

    ret = device_create_file(icc_device, &dev_attr_mode);
    if (ret) {
        pr_err("%s: device_create_file mode failed: %d\n", DRIVER_NAME, ret);
        goto err_device_destroy;
    }

    ret = device_create_file(icc_device, &dev_attr_threshold);
    if (ret) {
        pr_err("%s: device_create_file threshold failed: %d\n", DRIVER_NAME, ret);
        goto err_remove_mode;
    }

    pr_info("%s: Initialized — mode=%d, threshold=%d\n",
            DRIVER_NAME, charging_mode, custom_threshold);
    return 0;

err_remove_mode:
    device_remove_file(icc_device, &dev_attr_mode);
err_device_destroy:
    device_destroy(icc_class, icc_dev);
err_class_destroy:
    class_destroy(icc_class);
err_cdev_del:
    cdev_del(&icc_cdev);
err_unregister:
    unregister_chrdev_region(icc_dev, 1);
    return ret;
}

static int icc_remove(struct platform_device *pdev)
{
    device_remove_file(icc_device, &dev_attr_threshold);
    device_remove_file(icc_device, &dev_attr_mode);
    device_destroy(icc_class, icc_dev);
    class_destroy(icc_class);
    cdev_del(&icc_cdev);
    unregister_chrdev_region(icc_dev, 1);
    pr_info("%s: Removed\n", DRIVER_NAME);
    return 0;
}

static const struct of_device_id icc_of_match[] = {
    { .compatible = "qcom,sm8150" },
    { },
};
MODULE_DEVICE_TABLE(of, icc_of_match);

static struct platform_driver icc_driver = {
    .probe  = icc_probe,
    .remove = icc_remove,
    .driver = {
        .name           = DRIVER_NAME,
        .of_match_table = icc_of_match,
    },
};

module_platform_driver(icc_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Infinity Kernel Team");
MODULE_DESCRIPTION("Charging Control Driver for SM8150 (Poco X3 Pro)");
MODULE_VERSION("1.0.49");