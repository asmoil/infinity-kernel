/*
 * Infinity Charging Control — Header v1.0.35
 * SM8250-AC (Poco X3 Pro) | Linux 4.14
 */

#ifndef _INFINITY_CHARGING_CONTROL_H
#define _INFINITY_CHARGING_CONTROL_H

#include <linux/ioctl.h>

/* Charging modes */
enum charging_mode {
    CHARGING_MODE_BYPASS    = 0,  /* Stop charging, run on battery */
    CHARGING_MODE_NORMAL    = 1,  /* Default, charge to 100% */
    CHARGING_MODE_LIMIT_80  = 2,  /* Stop at 80% */
    CHARGING_MODE_LIMIT_90  = 3,  /* Stop at 90% */
};

/* IOCTL magic */
#define INFINITY_IOC_MAGIC 'I'

/* IOCTL: set charging mode */
#define INFINITY_IOCTL_SET_MODE    _IOW(INFINITY_IOC_MAGIC, 1, int)

/* IOCTL: get current mode */
#define INFINITY_IOCTL_GET_MODE    _IOR(INFINITY_IOC_MAGIC, 2, int)

/* IOCTL: get battery capacity */
#define INFINITY_IOCTL_GET_CAPACITY _IOR(INFINITY_IOC_MAGIC, 3, int)

/* Request structure for IOCTL */
struct infinity_charging_req {
    int mode;       /* charging mode (0-3) */
    int capacity;   /* battery capacity (read only) */
    int threshold;  /* charge limit threshold */
    int status;     /* current charger status */
};

#endif /* _INFINITY_CHARGING_CONTROL_H */