#!/usr/bin/env bash
# Patch 02: NTsync Driver
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_NTSYNC_PATCHED"
grep -q "$MARKER" "${KDIR}/drivers/ntsync/ntsync.c" 2>/dev/null && {
    echo "[02-ntsync] Already patched, skipping"
    exit 0
}

echo "[02-ntsync] Creating NTsync driver..."

# Create directories
mkdir -p "${KDIR}/drivers/ntsync"
mkdir -p "${KDIR}/include/uapi/linux"

# ========================================
# UAPI header
# ========================================
cat > "${KDIR}/include/uapi/linux/ntsync.h" << 'UAPIEOF'
/* SPDX-License-Identifier: GPL-2.0-only WITH Linux-syscall-note */
#ifndef _UAPI_LINUX_NTSYNC_H
#define _UAPI_LINUX_NTSYNC_H

#include <linux/ioctl.h>
#include <linux/types.h>

struct ntsync_sem_args {
        __u32 count;
        __u32 max;
        __u32 sem;
};

struct ntsync_mutex_args {
        __u32 mutex;
        __u32 owner;
};

struct ntsync_event_args {
        __u32 event;
        __u32 manual;
        __u32 signaled;
};

struct ntsync_sem_post_args {
        __u32 sem;
        __u32 count;
};

struct ntsync_wait_args {
        __u32 obj;
        __u32 owner;
        __u32 pad;
};

struct ntsync_wait_all_args {
        __u64 objs;
        __u32 count;
        __u32 owner;
        __u32 all;
        __u32 pad;
};

#define NTSYNC_IOC_BASE         0xf0

#define NTSYNC_IOC_CREATE_SEM           _IOWR(NTSYNC_IOC_BASE, 0, struct ntsync_sem_args)
#define NTSYNC_IOC_CREATE_MUTEX _IOWR(NTSYNC_IOC_BASE, 1, struct ntsync_mutex_args)
#define NTSYNC_IOC_CREATE_EVENT _IOWR(NTSYNC_IOC_BASE, 2, struct ntsync_event_args)
#define NTSYNC_IOC_SEM_POST             _IOW(NTSYNC_IOC_BASE, 3, struct ntsync_sem_post_args)
#define NTSYNC_IOC_SEM_WAIT             _IOW(NTSYNC_IOC_BASE, 4, struct ntsync_wait_args)
#define NTSYNC_IOC_MUTEX_ACQUIRE        _IOWR(NTSYNC_IOC_BASE, 5, struct ntsync_mutex_args)
#define NTSYNC_IOC_MUTEX_RELEASE        _IOW(NTSYNC_IOC_BASE, 6, struct ntsync_mutex_args)
#define NTSYNC_IOC_EVENT_SET            _IOW(NTSYNC_IOC_BASE, 7, struct ntsync_event_args)
#define NTSYNC_IOC_EVENT_RESET  _IOW(NTSYNC_IOC_BASE, 8, struct ntsync_event_args)
#define NTSYNC_IOC_WAIT                 _IOW(NTSYNC_IOC_BASE, 9, struct ntsync_wait_all_args)

#endif /* _UAPI_LINUX_NTSYNC_H */
UAPIEOF
echo "[02-ntsync] UAPI header created"

# ========================================
# ntsync.c - Real NT Synchronization Primitives
# ========================================
cat > "${KDIR}/drivers/ntsync/ntsync.c" << 'NTSYNC_EOF'
/*
 * ntsync.c - NT synchronization primitives driver
 * Implements semaphore, mutex, and event objects for Wine/Proton compatibility
 *
 * SPDX-License-Identifier: GPL-2.0-only
 * Copyright (c) 2024 Infinity Kernel Team
 */

#include <linux/anon_inodes.h>
#include <linux/atomic.h>
#include <linux/file.h>
#include <linux/fs.h>
#include <linux/idr.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/kref.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/uaccess.h>
#include <linux/wait.h>
#include <uapi/linux/ntsync.h>

/*
 * Object types
 */
enum ntsync_type {
        NTSYNC_TYPE_SEM,
        NTSYNC_TYPE_MUTEX,
        NTSYNC_TYPE_EVENT,
};

struct ntsync_obj;

/*
 * Per-object wait queue entry
 */
struct ntsync_waiter {
        struct list_head task_entry;
        struct list_head obj_entry;
        struct task_struct *task;
        struct ntsync_obj *obj;
        __u32 owner;
        bool signaled;
};

/*
 * Base synchronization object
 */
struct ntsync_obj {
        struct kref refcount;
        spinlock_t lock;

        enum ntsync_type type;

        /* Device that owns this object */
        struct ntsync_device *dev;

        /* All waiters on this object */
        struct list_head waiters;

        union {
                struct {
                        __u32 count;
                        __u32 max;
                } sem;
                struct {
                        __u32 count;
                        __u32 owner;
                        bool abandoned;
                } mutex;
                struct {
                        bool manual;
                        bool signaled;
                } event;
        };

        /* ID for user-space reference */
        int id;
        struct rcu_head rcu;
};

/*
 * Device context (per-open-file)
 */
struct ntsync_device {
        struct file *file;
        struct mutex dev_lock;
        struct idr objects_idr;
};

static void ntsync_obj_release(struct kref *ref)
{
        struct ntsync_obj *obj = container_of(ref, struct ntsync_obj, refcount);

        kfree(obj);
}

static void ntsync_obj_put(struct ntsync_obj *obj)
{
        kref_put(&obj->refcount, ntsync_obj_release);
}

static struct ntsync_obj *ntsync_obj_get(struct ntsync_obj *obj)
{
        kref_get(&obj->refcount);
        return obj;
}

/*
 * Try to wake up waiters on this object.
 * Called with obj->lock held.
 */
static void ntsync_wake_any(struct ntsync_obj *obj)
{
        struct ntsync_waiter *waiter, *next;

        list_for_each_entry_safe(waiter, next, &obj->waiters, obj_entry) {
                if (waiter->signaled)
                        continue;
                waiter->signaled = true;
                wake_up_process(waiter->task);
                break; /* Wake only one waiter */
        }
}

/*
 * Signal all waiters on this object (for events)
 * Called with obj->lock held.
 */
static void ntsync_wake_all(struct ntsync_obj *obj)
{
        struct ntsync_waiter *waiter;

        list_for_each_entry(waiter, &obj->waiters, obj_entry) {
                if (waiter->signaled)
                        continue;
                waiter->signaled = true;
                wake_up_process(waiter->task);
        }
}

/*
 * Check if an object is currently signaled
 */
static bool ntsync_is_signaled(struct ntsync_obj *obj, __u32 owner)
{
        bool signaled = false;

        switch (obj->type) {
        case NTSYNC_TYPE_SEM:
                signaled = obj->sem.count > 0;
                break;
        case NTSYNC_TYPE_MUTEX:
                if (obj->mutex.count == 0)
                        signaled = true;
                else if (obj->mutex.owner == owner)
                        signaled = true;
                else if (obj->mutex.abandoned)
                        signaled = true;
                break;
        case NTSYNC_TYPE_EVENT:
                signaled = obj->event.signaled;
                break;
        }
        return signaled;
}

/*
 * Create a semaphore
 */
static int ntsync_create_sem(struct ntsync_device *dev, void __user *argp)
{
        struct ntsync_sem_args __user *user_args = argp;
        struct ntsync_sem_args args;
        struct ntsync_obj *obj;
        int ret, id;

        if (copy_from_user(&args, user_args, sizeof(args)))
                return -EFAULT;

        if (args.count > args.max)
                return -EINVAL;

        obj = kzalloc(sizeof(*obj), GFP_KERNEL);
        if (!obj)
                return -ENOMEM;

        kref_init(&obj->refcount);
        spin_lock_init(&obj->lock);
        INIT_LIST_HEAD(&obj->waiters);
        obj->type = NTSYNC_TYPE_SEM;
        obj->dev = dev;
        obj->sem.count = args.count;
        obj->sem.max = args.max;

        mutex_lock(&dev->dev_lock);
        id = idr_alloc(&dev->objects_idr, obj, 1, 0, GFP_KERNEL);
        mutex_unlock(&dev->dev_lock);

        if (id < 0) {
                kfree(obj);
                return id;
        }

        obj->id = id;

        ret = put_user(id, &user_args->sem);
        if (ret) {
                mutex_lock(&dev->dev_lock);
                idr_remove(&dev->objects_idr, id);
                mutex_unlock(&dev->dev_lock);
                ntsync_obj_put(obj);
                return ret;
        }

        return 0;
}

/*
 * Create a mutex
 */
static int ntsync_create_mutex(struct ntsync_device *dev, void __user *argp)
{
        struct ntsync_mutex_args __user *user_args = argp;
        struct ntsync_mutex_args args;
        struct ntsync_obj *obj;
        int ret, id;

        if (copy_from_user(&args, user_args, sizeof(args)))
                return -EFAULT;

        obj = kzalloc(sizeof(*obj), GFP_KERNEL);
        if (!obj)
                return -ENOMEM;

        kref_init(&obj->refcount);
        spin_lock_init(&obj->lock);
        INIT_LIST_HEAD(&obj->waiters);
        obj->type = NTSYNC_TYPE_MUTEX;
        obj->dev = dev;
        obj->mutex.count = args.owner ? 1 : 0;
        obj->mutex.owner = args.owner;
        obj->mutex.abandoned = false;

        mutex_lock(&dev->dev_lock);
        id = idr_alloc(&dev->objects_idr, obj, 1, 0, GFP_KERNEL);
        mutex_unlock(&dev->dev_lock);

        if (id < 0) {
                kfree(obj);
                return id;
        }

        obj->id = id;

        ret = put_user(id, &user_args->mutex);
        if (ret) {
                mutex_lock(&dev->dev_lock);
                idr_remove(&dev->objects_idr, id);
                mutex_unlock(&dev->dev_lock);
                ntsync_obj_put(obj);
                return ret;
        }

        return 0;
}

/*
 * Create an event
 */
static int ntsync_create_event(struct ntsync_device *dev, void __user *argp)
{
        struct ntsync_event_args __user *user_args = argp;
        struct ntsync_event_args args;
        struct ntsync_obj *obj;
        int ret, id;

        if (copy_from_user(&args, user_args, sizeof(args)))
                return -EFAULT;

        obj = kzalloc(sizeof(*obj), GFP_KERNEL);
        if (!obj)
                return -ENOMEM;

        kref_init(&obj->refcount);
        spin_lock_init(&obj->lock);
        INIT_LIST_HEAD(&obj->waiters);
        obj->type = NTSYNC_TYPE_EVENT;
        obj->dev = dev;
        obj->event.manual = args.manual;
        obj->event.signaled = args.signaled;

        mutex_lock(&dev->dev_lock);
        id = idr_alloc(&dev->objects_idr, obj, 1, 0, GFP_KERNEL);
        mutex_unlock(&dev->dev_lock);

        if (id < 0) {
                kfree(obj);
                return id;
        }

        obj->id = id;

        ret = put_user(id, &user_args->event);
        if (ret) {
                mutex_lock(&dev->dev_lock);
                idr_remove(&dev->objects_idr, id);
                mutex_unlock(&dev->dev_lock);
                ntsync_obj_put(obj);
                return ret;
        }

        return 0;
}

/*
 * Post (release) a semaphore
 */
static int ntsync_sem_post(struct ntsync_device *dev, void __user *argp)
{
        struct ntsync_sem_post_args __user *user_args = argp;
        struct ntsync_sem_post_args args;
        struct ntsync_obj *obj;
        unsigned long flags;

        if (copy_from_user(&args, user_args, sizeof(args)))
                return -EFAULT;

        mutex_lock(&dev->dev_lock);
        obj = idr_find(&dev->objects_idr, args.sem);
        if (obj)
                ntsync_obj_get(obj);
        mutex_unlock(&dev->dev_lock);

        if (!obj)
                return -EINVAL;
        if (obj->type != NTSYNC_TYPE_SEM) {
                ntsync_obj_put(obj);
                return -EINVAL;
        }

        spin_lock_irqsave(&obj->lock, flags);

        if (obj->sem.count == UINT_MAX || obj->sem.count + args.count < args.count) {
                spin_unlock_irqrestore(&obj->lock, flags);
                ntsync_obj_put(obj);
                return -EOVERFLOW;
        }

        obj->sem.count += args.count;
        if (obj->sem.count > obj->sem.max)
                obj->sem.count = obj->sem.max;

        ntsync_wake_any(obj);

        spin_unlock_irqrestore(&obj->lock, flags);

        ntsync_obj_put(obj);
        return 0;
}

/*
 * Wait on a semaphore (decrement count)
 */
static int ntsync_sem_wait(struct ntsync_device *dev, void __user *argp)
{
        struct ntsync_wait_args __user *user_args = argp;
        struct ntsync_wait_args args;
        struct ntsync_obj *obj;
        unsigned long flags;
        int ret = 0;

        if (copy_from_user(&args, user_args, sizeof(args)))
                return -EFAULT;

        mutex_lock(&dev->dev_lock);
        obj = idr_find(&dev->objects_idr, args.obj);
        if (obj)
                ntsync_obj_get(obj);
        mutex_unlock(&dev->dev_lock);

        if (!obj)
                return -EINVAL;
        if (obj->type != NTSYNC_TYPE_SEM) {
                ntsync_obj_put(obj);
                return -EINVAL;
        }

        spin_lock_irqsave(&obj->lock, flags);

        while (obj->sem.count == 0) {
                DEFINE_WAIT(wait);
                struct ntsync_waiter waiter = {
                        .task = current,
                        .obj = obj,
                        .owner = args.owner,
                        .signaled = false,
                };

                if (signal_pending(current)) {
                        ret = -ERESTARTSYS;
                        break;
                }

                list_add_tail(&waiter.obj_entry, &obj->waiters);

                spin_unlock_irqrestore(&obj->lock, flags);
                schedule();
                spin_lock_irqsave(&obj->lock, flags);

                list_del(&waiter.obj_entry);

                if (waiter.signaled)
                        break;
        }

        if (ret == 0 && obj->sem.count > 0)
                obj->sem.count--;

        spin_unlock_irqrestore(&obj->lock, flags);
        ntsync_obj_put(obj);
        return ret;
}

/*
 * Acquire a mutex
 */
static int ntsync_mutex_acquire(struct ntsync_device *dev, void __user *argp)
{
        struct ntsync_mutex_args __user *user_args = argp;
        struct ntsync_mutex_args args;
        struct ntsync_obj *obj;
        unsigned long flags;
        int ret = 0;

        if (copy_from_user(&args, user_args, sizeof(args)))
                return -EFAULT;

        mutex_lock(&dev->dev_lock);
        obj = idr_find(&dev->objects_idr, args.mutex);
        if (obj)
                ntsync_obj_get(obj);
        mutex_unlock(&dev->dev_lock);

        if (!obj)
                return -EINVAL;
        if (obj->type != NTSYNC_TYPE_MUTEX) {
                ntsync_obj_put(obj);
                return -EINVAL;
        }

        spin_lock_irqsave(&obj->lock, flags);

        /* Recursive acquire by same owner is allowed */
        if (obj->mutex.owner == args.owner) {
                obj->mutex.count++;
                spin_unlock_irqrestore(&obj->lock, flags);
                ntsync_obj_put(obj);
                return 0;
        }

        while (obj->mutex.count != 0) {
                struct ntsync_waiter waiter = {
                        .task = current,
                        .obj = obj,
                        .owner = args.owner,
                        .signaled = false,
                };

                if (signal_pending(current)) {
                        ret = -ERESTARTSYS;
                        break;
                }

                /* Check for abandoned mutex */
                if (obj->mutex.abandoned) {
                        obj->mutex.abandoned = false;
                        ret = -EOWNERDEAD;
                        break;
                }

                list_add_tail(&waiter.obj_entry, &obj->waiters);

                spin_unlock_irqrestore(&obj->lock, flags);
                schedule();
                spin_lock_irqsave(&obj->lock, flags);

                list_del(&waiter.obj_entry);

                if (waiter.signaled)
                        break;
        }

        if (ret == 0 || ret == -EOWNERDEAD) {
                obj->mutex.count = 1;
                obj->mutex.owner = args.owner;
        }

        spin_unlock_irqrestore(&obj->lock, flags);
        ntsync_obj_put(obj);
        return ret;
}

/*
 * Release a mutex
 */
static int ntsync_mutex_release(struct ntsync_device *dev, void __user *argp)
{
        struct ntsync_mutex_args __user *user_args = argp;
        struct ntsync_mutex_args args;
        struct ntsync_obj *obj;
        unsigned long flags;

        if (copy_from_user(&args, user_args, sizeof(args)))
                return -EFAULT;

        mutex_lock(&dev->dev_lock);
        obj = idr_find(&dev->objects_idr, args.mutex);
        if (obj)
                ntsync_obj_get(obj);
        mutex_unlock(&dev->dev_lock);

        if (!obj)
                return -EINVAL;
        if (obj->type != NTSYNC_TYPE_MUTEX) {
                ntsync_obj_put(obj);
                return -EINVAL;
        }

        spin_lock_irqsave(&obj->lock, flags);

        if (obj->mutex.owner != args.owner) {
                spin_unlock_irqrestore(&obj->lock, flags);
                ntsync_obj_put(obj);
                return -EPERM;
        }

        if (obj->mutex.count > 1) {
                obj->mutex.count--;
        } else {
                obj->mutex.count = 0;
                obj->mutex.owner = 0;
                ntsync_wake_any(obj);
        }

        spin_unlock_irqrestore(&obj->lock, flags);
        ntsync_obj_put(obj);
        return 0;
}

/*
 * Set an event to signaled
 */
static int ntsync_event_set(struct ntsync_device *dev, void __user *argp)
{
        struct ntsync_event_args __user *user_args = argp;
        struct ntsync_event_args args;
        struct ntsync_obj *obj;
        unsigned long flags;

        if (copy_from_user(&args, user_args, sizeof(args)))
                return -EFAULT;

        mutex_lock(&dev->dev_lock);
        obj = idr_find(&dev->objects_idr, args.event);
        if (obj)
                ntsync_obj_get(obj);
        mutex_unlock(&dev->dev_lock);

        if (!obj)
                return -EINVAL;
        if (obj->type != NTSYNC_TYPE_EVENT) {
                ntsync_obj_put(obj);
                return -EINVAL;
        }

        spin_lock_irqsave(&obj->lock, flags);

        if (!obj->event.signaled) {
                obj->event.signaled = true;
                ntsync_wake_all(obj);
        }

        spin_unlock_irqrestore(&obj->lock, flags);
        ntsync_obj_put(obj);
        return 0;
}

/*
 * Reset an event to non-signaled
 */
static int ntsync_event_reset(struct ntsync_device *dev, void __user *argp)
{
        struct ntsync_event_args __user *user_args = argp;
        struct ntsync_event_args args;
        struct ntsync_obj *obj;
        unsigned long flags;

        if (copy_from_user(&args, user_args, sizeof(args)))
                return -EFAULT;

        mutex_lock(&dev->dev_lock);
        obj = idr_find(&dev->objects_idr, args.event);
        if (obj)
                ntsync_obj_get(obj);
        mutex_unlock(&dev->dev_lock);

        if (!obj)
                return -EINVAL;
        if (obj->type != NTSYNC_TYPE_EVENT) {
                ntsync_obj_put(obj);
                return -EINVAL;
        }

        spin_lock_irqsave(&obj->lock, flags);
        obj->event.signaled = false;
        spin_unlock_irqrestore(&obj->lock, flags);

        ntsync_obj_put(obj);
        return 0;
}

/*
 * Wait on multiple objects (any or all)
 */
static int ntsync_wait(struct ntsync_device *dev, void __user *argp)
{
        struct ntsync_wait_all_args __user *user_args = argp;
        struct ntsync_wait_all_args args;
        const __user __u32 *objs_ptr;
        __u32 *obj_ids;
        struct ntsync_obj **objs;
        unsigned long flags;
        int ret = 0, i;

        if (copy_from_user(&args, user_args, sizeof(args)))
                return -EFAULT;

        if (args.count == 0 || args.count > 64)
                return -EINVAL;

        objs_ptr = (__user __u32 *)(unsigned long)args.objs;

        obj_ids = kmalloc_array(args.count, sizeof(__u32), GFP_KERNEL);
        objs = kmalloc_array(args.count, sizeof(struct ntsync_obj *), GFP_KERNEL);
        if (!obj_ids || !objs) {
                kfree(obj_ids);
                kfree(objs);
                return -ENOMEM;
        }

        if (copy_from_user(obj_ids, objs_ptr, args.count * sizeof(__u32))) {
                kfree(obj_ids);
                kfree(objs);
                return -EFAULT;
        }

        /* Look up all objects */
        mutex_lock(&dev->dev_lock);
        for (i = 0; i < args.count; i++) {
                objs[i] = idr_find(&dev->objects_idr, obj_ids[i]);
                if (!objs[i]) {
                        mutex_unlock(&dev->dev_lock);
                        kfree(obj_ids);
                        kfree(objs);
                        return -EINVAL;
                }
                ntsync_obj_get(objs[i]);
        }
        mutex_unlock(&dev->dev_lock);

        kfree(obj_ids);

        /* Wait loop */
        for (;;) {
                bool all_signaled = true;
                int any_signaled_idx = -1;

                for (i = 0; i < args.count; i++) {
                        bool signaled;

                        spin_lock_irqsave(&objs[i]->lock, flags);
                        signaled = ntsync_is_signaled(objs[i], args.owner);
                        spin_unlock_irqrestore(&objs[i]->lock, flags);

                        if (!signaled) {
                                all_signaled = false;
                        } else if (any_signaled_idx < 0 && !args.all) {
                                any_signaled_idx = i;
                                break;
                        }
                }

                if ((args.all && all_signaled) || (!args.all && any_signaled_idx >= 0))
                        break;

                if (signal_pending(current)) {
                        ret = -ERESTARTSYS;
                        break;
                }

                schedule_timeout_interruptible(HZ / 10);
        }

        /* Acquire/modify objects on success */
        if (ret == 0) {
                for (i = 0; i < args.count; i++) {
                        spin_lock_irqsave(&objs[i]->lock, flags);
                        if (objs[i]->type == NTSYNC_TYPE_SEM && objs[i]->sem.count > 0)
                                objs[i]->sem.count--;
                        else if (objs[i]->type == NTSYNC_TYPE_MUTEX && objs[i]->mutex.count == 0) {
                                objs[i]->mutex.count = 1;
                                objs[i]->mutex.owner = args.owner;
                        }
                        spin_unlock_irqrestore(&objs[i]->lock, flags);
                }
        }

        for (i = 0; i < args.count; i++)
                ntsync_obj_put(objs[i]);
        kfree(objs);

        return ret;
}

/*
 * Device ioctl handler
 */
static long ntsync_dev_ioctl(struct file *file, unsigned int cmd,
                             unsigned long arg)
{
        struct ntsync_device *dev = file->private_data;
        void __user *argp = (void __user *)arg;

        switch (cmd) {
        case NTSYNC_IOC_CREATE_SEM:
                return ntsync_create_sem(dev, argp);
        case NTSYNC_IOC_CREATE_MUTEX:
                return ntsync_create_mutex(dev, argp);
        case NTSYNC_IOC_CREATE_EVENT:
                return ntsync_create_event(dev, argp);
        case NTSYNC_IOC_SEM_POST:
                return ntsync_sem_post(dev, argp);
        case NTSYNC_IOC_SEM_WAIT:
                return ntsync_sem_wait(dev, argp);
        case NTSYNC_IOC_MUTEX_ACQUIRE:
                return ntsync_mutex_acquire(dev, argp);
        case NTSYNC_IOC_MUTEX_RELEASE:
                return ntsync_mutex_release(dev, argp);
        case NTSYNC_IOC_EVENT_SET:
                return ntsync_event_set(dev, argp);
        case NTSYNC_IOC_EVENT_RESET:
                return ntsync_event_reset(dev, argp);
        case NTSYNC_IOC_WAIT:
                return ntsync_wait(dev, argp);
        default:
                return -ENOTTY;
        }
}

static int ntsync_dev_open(struct inode *inode, struct file *file)
{
        struct ntsync_device *dev;

        dev = kzalloc(sizeof(*dev), GFP_KERNEL);
        if (!dev)
                return -ENOMEM;

        mutex_init(&dev->dev_lock);
        idr_init(&dev->objects_idr);
        file->private_data = dev;

        return 0;
}

static int ntsync_dev_release(struct inode *inode, struct file *file)
{
        struct ntsync_device *dev = file->private_data;
        struct ntsync_obj *obj;
        int id;

        /* Clean up all objects */
        idr_for_each_entry(&dev->objects_idr, obj, id)
                ntsync_obj_put(obj);
        idr_destroy(&dev->objects_idr);

        kfree(dev);
        return 0;
}

static const struct file_operations ntsync_fops = {
        .owner                  = THIS_MODULE,
        .open                   = ntsync_dev_open,
        .release                = ntsync_dev_release,
        .unlocked_ioctl         = ntsync_dev_ioctl,
        .compat_ioctl           = compat_ptr_ioctl,
        .llseek                 = no_llseek,
};

static struct miscdevice ntsync_misc = {
        .minor  = MISC_DYNAMIC_MINOR,
        .name   = "ntsync",
        .fops   = &ntsync_fops,
};

/* Marker for idempotent patching */
#define INFINITY_NTSYNC_PATCHED 1

static int __init ntsync_init(void)
{
        return misc_register(&ntsync_misc);
}

static void __exit ntsync_exit(void)
{
        misc_deregister(&ntsync_misc);
}

module_init(ntsync_init);
module_exit(ntsync_exit);

MODULE_AUTHOR("Infinity Kernel Team");
MODULE_DESCRIPTION("NT synchronization primitives for Wine/Proton");
MODULE_LICENSE("GPL");
NTSYNC_EOF

echo "[02-ntsync] ntsync.c created ($(wc -l < "${KDIR}/drivers/ntsync/ntsync.c") lines)"

# ========================================
# Kconfig
# ========================================
cat > "${KDIR}/drivers/ntsync/Kconfig" << 'EOF'
# SPDX-License-Identifier: GPL-2.0-only
config NTSYNC
        tristate "NT synchronization primitive driver"
        default m
        depends on GENERIC_IO
        help
          This kernel module provides NT synchronization primitives
          (semaphore, mutex, event) for use by Wine and Proton compatibility
          layers on Android/arm64.

          Provides a misc device /dev/ntsync with ioctl interface for
          creating and operating on NT sync objects.

          If unsure, say N.
EOF

# ========================================
# Makefile
# ========================================
cat > "${KDIR}/drivers/ntsync/Makefile" << 'EOF'
# SPDX-License-Identifier: GPL-2.0-only
obj-$(CONFIG_NTSYNC)    += ntsync.o
EOF

# ========================================
# Patch drivers/Kconfig
# ========================================
if ! grep -q "source \"drivers/ntsync/Kconfig\"" "${KDIR}/drivers/Kconfig" 2>/dev/null; then
    sed -i '/source "drivers\/nvdimm\/Kconfig"/a source "drivers/ntsync/Kconfig"' "${KDIR}/drivers/Kconfig"
    echo "[02-ntsync] Patched drivers/Kconfig"
fi

# ========================================
# Patch drivers/Makefile
# ========================================
if ! grep -q "ntsync" "${KDIR}/drivers/Makefile" 2>/dev/null; then
    sed -i '/obj-$(CONFIG_NVDIMM_PMEM)/a obj-$(CONFIG_NTSYNC)           += ntsync/' "${KDIR}/drivers/Makefile"
    echo "[02-ntsync] Patched drivers/Makefile"
fi

echo "[02-ntsync] Done"