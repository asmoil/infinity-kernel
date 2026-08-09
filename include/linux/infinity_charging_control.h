#ifndef __LINUX_INFINITY_CHARGING_CONTROL_H
#define __LINUX_INFINITY_CHARGING_CONTROL_H

#include <linux/types.h>
#include <linux/ioctl.h>
#include <linux/device.h>

enum infinity_charging_mode {
	CHARGING_MODE_OFF       = 0,
	CHARGING_MODE_LIGHT     = 1,
	CHARGING_MODE_BALANCED  = 2,
	CHARGING_MODE_EXTREME   = 3,
	CHARGING_MODE_ULTRA     = 4,
};

enum infinity_thermal_limit {
	THERMAL_LIMIT_DISABLED  = 0,
	THERMAL_LIMIT_45C       = 45,
	THERMAL_LIMIT_40C       = 40,
	THERMAL_LIMIT_35C       = 35,
};

struct infinity_charging_status {
	__u32 mode;
	__s32 battery_voltage;
	__s32 battery_current;
	__s32 battery_temp;
	__u8  is_charging;
	__u8  thermal_throttled;
	__u8  bypass_active;
};

#define INFINITY_CHARGING_MAGIC 0xCC

#define INFINITY_CHARGING_SET_MODE          _IOW(INFINITY_CHARGING_MAGIC, 1, int)
#define INFINITY_CHARGING_GET_STATUS        _IOR(INFINITY_CHARGING_MAGIC, 2, struct infinity_charging_status)
#define INFINITY_CHARGING_SET_THERMAL_LIMIT _IOW(INFINITY_CHARGING_MAGIC, 3, int)
#define INFINITY_CHARGING_SET_AUTO_RESUME   _IOW(INFINITY_CHARGING_MAGIC, 4, int)

extern struct platform_driver infinity_charging_driver;

#endif