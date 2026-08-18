#!/usr/bin/env bash
# Patch 03: BORE Scheduler
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_BORE_PATCHED"
grep -q "$MARKER" "${KDIR}/kernel/sched/bore.h" 2>/dev/null && {
    echo "[03-scheduler-bore] Already patched, skipping"
    exit 0
}

echo "[03-scheduler-bore] Applying BORE scheduler..."

# ========================================
# Create kernel/sched/bore.h
# ========================================
cat > "${KDIR}/kernel/sched/bore.h" << 'BORE_EOF'
/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * BORE (Burst-Oriented Response Enhancer) Scheduler
 * Copyright (c) 2024 Infinity Kernel Team
 * Based on BORE by Masahito Suzuki (firelzrd)
 */

#ifndef _KERNEL_SCHED_BORE_H
#define _KERNEL_SCHED_BORE_H

#include <linux/sched.h>
#include <linux/math64.h>

/*
 * BORE configuration constants
 */
#define SCHED_BORE_MIN_MAX_BURST_SCORE   0
#define SCHED_BORE_MAX_MAX_BURST_SCORE   1000U
#define SCHED_BORE_DEFAULT_BURST_PENALTY  12U
#define SCHED_BORE_BURST_PENALTY_MAX     24U
#define SCHED_BORE_BURST_PENALTY_MIN     0U

#define SCHED_BORE_VRANGE_MAX           80LL
#define SCHED_BORE_VRANGE_MIN          -80LL

#define SCHED_BORE_GREEDY_THRESHOLD     50
#define SCHED_BORE_INTERACTIVE_LATENCY  5000   /* 5ms */
#define SCHED_BORE_SLICE_BOOST          1.25

#ifdef CONFIG_SCHED_BORE

/*
 * Burst state structure, attached to each task's sched_entity
 */
struct sched_burst {
	/*
	 * Number of consecutive bursts this task has executed.
	 * Incremented when a task starts a new burst.
	 * Reset to 0 after a period of inactivity.
	 */
	unsigned int burst_count;

	/*
	 * Timestamp (in ns) of the last burst start.
	 * Used to compute burst duration.
	 */
	u64 last_burst_start;

	/*
	 * Duration of the most recent burst (ns).
	 */
	u64 burst_duration;

	/*
	 * Cumulative runtime within the current burst.
	 */
	u64 burst_runtime;

	/*
	 * The computed burst score for scheduling decisions.
	 * Higher values indicate more interactive behavior.
	 * Range: [0, SCHED_BORE_MAX_MAX_BURST_SCORE]
	 */
	u16 burst_score;

	/*
	 * Whether this task has been marked as interactive.
	 */
	bool interactive;

	/*
	 * Whether the task is currently in a burst (running
	 * consecutively without sleeping).
	 */
	bool in_burst;

	/*
	 * Accumulated virtual runtime bonus/penalty from
	 * burst score. Applied as vruntime adjustment.
	 */
	u64 vruntime_bonus;

	/*
	 * Time when the task last went to sleep.
	 * Used to detect inter-burst gaps.
	 */
	u64 last_sleep_time;

	/*
	 * Smoothed burst duration for adaptive scoring.
	 */
	u64 avg_burst_duration;

	/*
	 * Max burst penalty (0-24) that determines how much
	 * the burst score decays with successive bursts.
	 * Can be tuned via sysctl.
	 */
	u8 burst_penalty_max;
};

/*
 * Compute the burst score based on burst count and penalty.
 *
 * The score follows a curve:
 *   - Low burst counts yield higher scores (responsive)
 *   - High burst counts yield lower scores (CPU hogs get penalized)
 *   - The decay rate is controlled by burst_penalty_max
 *
 * Score formula:
 *   score = max_score * (penalty_max - effective_penalty) / penalty_max
 *   where effective_penalty = min(burst_count * penalty_step, penalty_max)
 */
static inline u16 sched_bore_compute_score(struct sched_burst *sb)
{
	u32 penalty_step, effective_penalty, score;
	u16 max_score = SCHED_BORE_MAX_MAX_BURST_SCORE;

	if (!sb || sb->burst_count == 0)
		return max_score;

	penalty_step = max_t(u32, 1, sb->burst_penalty_max / 8);
	effective_penalty = min_t(u32,
		sb->burst_count * penalty_step,
		(u32)sb->burst_penalty_max);

	/*
	 * Apply non-linear decay for better responsiveness.
	 * Square root curve gives more room at low burst counts.
	 */
	if (effective_penalty > 0) {
		effective_penalty = int_sqrt(effective_penalty * 100);
		effective_penalty = min_t(u32, effective_penalty, 100);
	}

	score = max_score * (100 - effective_penalty) / 100;
	score = max_t(u32, score, SCHED_BORE_MIN_MAX_BURST_SCORE);
	score = min_t(u32, score, SCHED_BORE_MAX_MAX_BURST_SCORE);

	sb->burst_score = (u16)score;
	return sb->burst_score;
}

/*
 * Update burst state when a task starts running.
 *
 * If the task was sleeping (gap > threshold), reset burst_count
 * and start a new burst. Otherwise, increment burst_count.
 */
static inline void sched_bore_start_burst(struct sched_burst *sb, u64 now)
{
	u64 gap;

	if (!sb)
		return;

	/* Compute gap since last sleep */
	if (sb->last_sleep_time > 0 && now > sb->last_sleep_time) {
		gap = now - sb->last_sleep_time;

		/*
		 * If gap is large enough, consider this a new
		 * interactive event and reset burst count.
		 */
		if (gap > (u64)SCHED_BORE_INTERACTIVE_LATENCY * NSEC_PER_USEC) {
			sb->burst_count = 0;
			sb->interactive = true;
		}
	} else {
		sb->interactive = false;
	}

	sb->in_burst = true;
	sb->last_burst_start = now;
	sb->burst_runtime = 0;
	sb->burst_count++;

	/* Recompute score */
	sched_bore_compute_score(sb);
}

/*
 * Update burst state when a task goes to sleep or is preempted.
 * Records the burst duration and updates the running average.
 */
static inline void sched_bore_end_burst(struct sched_burst *sb, u64 now)
{
	u64 duration;

	if (!sb || !sb->in_burst)
		return;

	sb->in_burst = false;

	if (now > sb->last_burst_start) {
		duration = now - sb->last_burst_start;
		sb->burst_duration = duration;

		/* Exponential moving average */
		if (sb->avg_burst_duration > 0) {
			sb->avg_burst_duration =
				(sb->avg_burst_duration * 3 + duration) / 4;
		} else {
			sb->avg_burst_duration = duration;
		}
	}

	sb->last_sleep_time = now;
}

/*
 * Compute the vruntime bonus/penalty based on burst score.
 *
 * High burst score (interactive) -> negative bonus (run sooner)
 * Low burst score (CPU hog)   -> positive bonus  (run later)
 *
 * The bonus is scaled by the base slice length to keep it
 * proportional to the scheduling granularity.
 */
static inline s64 sched_bore_vruntime_bonus(struct sched_burst *sb, u64 slice_ns)
{
	s64 bonus;
	s32 vrange = SCHED_BORE_VRANGE_MAX - SCHED_BORE_VRANGE_MIN;

	if (!sb)
		return 0;

	/*
	 * Map burst_score [0, 1000] to bonus [-80, +80] * slice
	 *
	 * score 1000 (interactive) -> -80 * slice (bonus, run sooner)
	 * score 500  (neutral)    ->  0  * slice
	 * score 0    (CPU hog)    -> +80 * slice (penalty, run later)
	 */
	bonus = SCHED_BORE_VRANGE_MAX;
	bonus -= (s64)sb->burst_score * vrange / SCHED_BORE_MAX_MAX_BURST_SCORE;

	/* Scale by slice */
	bonus = bonus * (s64)slice_ns / 1000LL;

	/* Clamp */
	bonus = clamp_t(s64, bonus,
			(s64)SCHED_BORE_VRANGE_MIN * (s64)slice_ns / 1000LL,
			(s64)SCHED_BORE_VRANGE_MAX * (s64)slice_ns / 1000LL);

	sb->vruntime_bonus = (u64)max_t(s64, 0, bonus);
	return bonus;
}

/*
 * Initialize burst structure for a new task.
 * Inherits parent's burst state if available (fork).
 */
static inline void sched_bore_init(struct sched_burst *sb,
				    struct sched_burst *parent_sb)
{
	if (!sb)
		return;

	if (parent_sb) {
		sb->burst_count = parent_sb->burst_count;
		sb->burst_penalty_max = parent_sb->burst_penalty_max;
		sb->avg_burst_duration = parent_sb->avg_burst_duration;
		sb->interactive = parent_sb->interactive;
	} else {
		sb->burst_count = 0;
		sb->burst_penalty_max = SCHED_BORE_DEFAULT_BURST_PENALTY;
		sb->avg_burst_duration = 0;
		sb->interactive = true; /* New tasks are interactive */
	}

	sb->last_burst_start = 0;
	sb->burst_duration = 0;
	sb->burst_runtime = 0;
	sb->burst_score = SCHED_BORE_MAX_MAX_BURST_SCORE;
	sb->in_burst = false;
	sb->vruntime_bonus = 0;
	sb->last_sleep_time = 0;
}

/*
 * Check if a task's slice should be boosted.
 * Interactive tasks with high burst scores get larger slices.
 */
static inline u64 sched_bore_slice_boost(struct sched_burst *sb, u64 base_slice)
{
	if (!sb)
		return base_slice;

	if (sb->burst_score > SCHED_BORE_GREEDY_THRESHOLD && sb->interactive) {
		/* Scale boost proportionally to score */
		u32 boost_pct = (u32)sb->burst_score * 25 / SCHED_BORE_MAX_MAX_BURST_SCORE;
		boost_pct = min_t(u32, boost_pct, 25); /* Max 25% boost */
		return base_slice * (100 + boost_pct) / 100;
	}

	return base_slice;
}

/* Marker for idempotent patching */
#define INFINITY_BORE_PATCHED 1

#endif /* CONFIG_SCHED_BORE */
#endif /* _KERNEL_SCHED_BORE_H */
BORE_EOF

echo "[03-scheduler-bore] Created kernel/sched/bore.h ($(wc -l < "${KDIR}/kernel/sched/bore.h") lines)"

# ========================================
# Patch kernel/sched/fair.c to use BORE
# ========================================
FAIR="${KDIR}/kernel/sched/fair.c"

if [ ! -f "$FAIR" ]; then
    echo "[03-scheduler-bore] WARNING: fair.c not found, skipping"
    exit 0
fi

# Add include of bore.h after existing includes
if ! grep -q "sched/bore.h" "$FAIR" 2>/dev/null; then
    sed -i '/#include "sched.h"/a #include "sched/bore.h"' "$FAIR"
    echo "[03-scheduler-bore] Added bore.h include to fair.c"
fi

# Patch pick_next_task_fair to apply BORE score
# Find the function and add BORE vruntime adjustment
if ! grep -q "sched_bore_vruntime_bonus" "$FAIR" 2>/dev/null; then
    sed -i '/pick_next_task_fair/,/^}/ {
        /se->vruntime +=/a \
	/* BORE: apply burst score vruntime bonus */
	{
		struct sched_burst __maybe_unused *sb = &p->se.burst;
		s64 bonus = sched_bore_vruntime_bonus(sb, sysctl_sched_min_granularity);
		se->vruntime -= max_t(s64, 0, -bonus); /* Negative bonus = run sooner */
	}
    }' "$FAIR"
    echo "[03-scheduler-bore] Patched pick_next_task_fair"
fi

# Patch entity_tick for burst tracking
if ! grep -q "sched_bore_end_burst" "$FAIR" 2>/dev/null; then
    sed -i '/entity_tick/,/^}/ {
        /curr->exec_start =/a \
	/* BORE: track burst state on tick */
	{
		u64 now = rq_clock_task(rq);
		sched_bore_start_burst(&curr->burst, now);
	}
    }' "$FAIR"
    echo "[03-scheduler-bore] Patched entity_tick"
fi

# ========================================
# Add Kconfig entry for BORE
# ========================================
KCONF="${KDIR}/kernel/sched/Kconfig"
if [ -f "$KCONF" ] && ! grep -q "SCHED_BORE" "$KCONF" 2>/dev/null; then
    cat >> "$KCONF" << 'KCFGEOF'

config SCHED_BORE
	bool "BORE (Burst-Oriented Response Enhancer) Scheduler"
	default y
	help
	  BORE improves desktop responsiveness by tracking task burst
	  patterns. Interactive tasks that run in short bursts receive
	  lower vruntime penalties, while CPU-bound tasks accumulate
	  penalties over successive bursts.

	  This results in snappier UI response under load while
	  maintaining fairness for background workloads.

	  If unsure, say Y.
KCFGEOF
    echo "[03-scheduler-bore] Added Kconfig entry"
fi

echo "[03-scheduler-bore] Done"