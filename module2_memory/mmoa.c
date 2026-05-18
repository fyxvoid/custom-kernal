// SPDX-License-Identifier: GPL-2.0
/*
 * Module 2: Memory Module Modification
 * Memory Management Optimization Algorithm (MMOA)
 *
 * A loadable kernel module that:
 *   1. Reads the current memory allocation pattern via perf events / kprobes
 *      and reports it through /proc/mmoa_stats.
 *   2. Applies sysctl-level tuning at load time (swappiness, min_free_kbytes,
 *      vfs_cache_pressure, watermark_scale_factor).
 *   3. Monitors /proc/buddyinfo fragmentation and triggers proactive compaction
 *      when the high-order fragmentation index exceeds a configurable threshold.
 *   4. Exposes a /proc/mmoa_control knob for runtime parameter adjustment.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/mm.h>
#include <linux/mmzone.h>
#include <linux/vmstat.h>
#include <linux/swap.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/workqueue.h>
#include <linux/timer.h>
#include <linux/jiffies.h>
#include <linux/atomic.h>
#include <linux/string.h>
#include <linux/compaction.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("SecureKernel Team");
MODULE_DESCRIPTION("MMOA: Memory Management Optimization for hardened kernel");
MODULE_VERSION("1.0");

/* ------------------------------------------------------------------ */
/* Module parameters                                                    */
/* ------------------------------------------------------------------ */

/* Swappiness: 10 = prefer reclaiming page cache over swap (embedded) */
static int mmoa_swappiness = 10;
module_param(mmoa_swappiness, int, 0644);
MODULE_PARM_DESC(mmoa_swappiness, "vm.swappiness value (default 10)");

/* min_free_kbytes multiplier relative to current default */
static int mmoa_min_free_mult = 2;
module_param(mmoa_min_free_mult, int, 0644);
MODULE_PARM_DESC(mmoa_min_free_mult, "Multiplier for vm.min_free_kbytes (default 2)");

/* vfs_cache_pressure: 150 = faster inode/dentry reclaim */
static int mmoa_vfs_cache_pressure = 150;
module_param(mmoa_vfs_cache_pressure, int, 0644);
MODULE_PARM_DESC(mmoa_vfs_cache_pressure, "vm.vfs_cache_pressure (default 150)");

/*
 * Fragmentation threshold: if the ratio of free pages at order >= 4
 * to total free pages drops below this percentage, trigger compaction.
 */
static int mmoa_frag_threshold = 20;
module_param(mmoa_frag_threshold, int, 0644);
MODULE_PARM_DESC(mmoa_frag_threshold, "Fragmentation threshold %% to trigger compaction");

/* Monitoring interval in seconds */
static int mmoa_monitor_interval = 30;
module_param(mmoa_monitor_interval, int, 0644);
MODULE_PARM_DESC(mmoa_monitor_interval, "Memory monitoring interval in seconds");

/* ------------------------------------------------------------------ */
/* Original sysctl values (restored on unload)                         */
/* ------------------------------------------------------------------ */

static int orig_swappiness;
static int orig_vfs_cache_pressure;
static unsigned long orig_min_free_kbytes;
static atomic64_t mmoa_compaction_count = ATOMIC64_INIT(0);
static atomic64_t mmoa_monitor_ticks    = ATOMIC64_INIT(0);

/* ------------------------------------------------------------------ */
/* Fragmentation measurement                                            */
/* ------------------------------------------------------------------ */

/**
 * mmoa_frag_index - compute a simple fragmentation index for a zone
 *
 * Returns the percentage of free pages that are in high-order blocks
 * (order >= 4, i.e., >= 64KB chunks). A low return value means the
 * zone is fragmented.
 */
static int mmoa_frag_index(struct zone *zone)
{
	unsigned long total_free = 0;
	unsigned long high_order_free = 0;
	int order;
	struct free_area *area;

	for (order = 0; order < MAX_ORDER; order++) {
		area = &zone->free_area[order];
		total_free += area->nr_free << order;
		if (order >= 4)
			high_order_free += area->nr_free << order;
	}

	if (total_free == 0)
		return 100; /* empty zone = no fragmentation */

	return (int)((high_order_free * 100) / total_free);
}

/* ------------------------------------------------------------------ */
/* Compaction trigger                                                   */
/* ------------------------------------------------------------------ */

static void mmoa_maybe_compact(void)
{
	struct zone *zone;

	for_each_populated_zone(zone) {
		int idx = mmoa_frag_index(zone);
		if (idx < mmoa_frag_threshold) {
			pr_info("MMOA: zone %s frag_index=%d%% < threshold=%d%%, triggering compaction\n",
				zone->name, idx, mmoa_frag_threshold);
			/* Request compaction for this zone */
			compact_zone_order(zone, MAX_ORDER - 1, GFP_KERNEL,
					   COMPACT_PRIO_SYNC_LIGHT, NULL);
			atomic64_inc(&mmoa_compaction_count);
		}
	}
}

/* ------------------------------------------------------------------ */
/* Periodic monitoring work                                             */
/* ------------------------------------------------------------------ */

static struct delayed_work mmoa_monitor_work;

static void mmoa_monitor_fn(struct work_struct *work)
{
	atomic64_inc(&mmoa_monitor_ticks);
	mmoa_maybe_compact();
	schedule_delayed_work(&mmoa_monitor_work,
			      msecs_to_jiffies(mmoa_monitor_interval * 1000));
}

/* ------------------------------------------------------------------ */
/* /proc/mmoa_stats                                                     */
/* ------------------------------------------------------------------ */

static int mmoa_stats_show(struct seq_file *m, void *v)
{
	struct zone *zone;
	int order;

	seq_puts(m, "MMOA Memory Management Optimization Module\n");
	seq_puts(m, "==========================================\n\n");

	seq_printf(m, "Parameters:\n");
	seq_printf(m, "  vm.swappiness           = %d\n", vm_swappiness);
	seq_printf(m, "  vm.min_free_kbytes      = %lu\n", min_free_kbytes);
	seq_printf(m, "  vm.vfs_cache_pressure   = %d\n", vfs_cache_pressure);
	seq_printf(m, "  frag_threshold          = %d%%\n", mmoa_frag_threshold);
	seq_printf(m, "  monitor_interval        = %ds\n\n", mmoa_monitor_interval);

	seq_printf(m, "Statistics:\n");
	seq_printf(m, "  monitor_ticks           = %lld\n",
		   atomic64_read(&mmoa_monitor_ticks));
	seq_printf(m, "  compaction_events       = %lld\n\n",
		   atomic64_read(&mmoa_compaction_count));

	seq_puts(m, "Zone Fragmentation:\n");
	seq_printf(m, "  %-20s %-10s %-10s\n", "Zone", "FreePages", "FragIndex%");
	seq_printf(m, "  %-20s %-10s %-10s\n", "----", "---------", "----------");

	for_each_populated_zone(zone) {
		unsigned long total_free = 0;
		int frag;
		for (order = 0; order < MAX_ORDER; order++)
			total_free += zone->free_area[order].nr_free << order;
		frag = mmoa_frag_index(zone);
		seq_printf(m, "  %-20s %-10lu %-10d\n",
			   zone->name, total_free, frag);
	}

	seq_puts(m, "\nBuddy Allocator (free blocks per order):\n");
	seq_printf(m, "  %-20s", "Zone");
	for (order = 0; order < MAX_ORDER; order++)
		seq_printf(m, " %5d", order);
	seq_puts(m, "\n");

	for_each_populated_zone(zone) {
		seq_printf(m, "  %-20s", zone->name);
		for (order = 0; order < MAX_ORDER; order++)
			seq_printf(m, " %5lu", zone->free_area[order].nr_free);
		seq_puts(m, "\n");
	}

	return 0;
}

static int mmoa_stats_open(struct inode *inode, struct file *file)
{
	return single_open(file, mmoa_stats_show, NULL);
}

static const struct proc_ops mmoa_stats_ops = {
	.proc_open    = mmoa_stats_open,
	.proc_read    = seq_read,
	.proc_lseek   = seq_lseek,
	.proc_release = single_release,
};

/* ------------------------------------------------------------------ */
/* /proc/mmoa_control                                                   */
/* ------------------------------------------------------------------ */

static ssize_t mmoa_control_write(struct file *file, const char __user *buf,
				   size_t count, loff_t *ppos)
{
	char kbuf[128];
	char cmd[32];
	int val;

	if (!capable(CAP_SYS_ADMIN))
		return -EPERM;
	if (count >= sizeof(kbuf))
		return -EINVAL;
	if (copy_from_user(kbuf, buf, count))
		return -EFAULT;
	kbuf[count] = '\0';
	if (count > 0 && kbuf[count - 1] == '\n')
		kbuf[count - 1] = '\0';

	if (sscanf(kbuf, "%31s %d", cmd, &val) != 2)
		return -EINVAL;

	if (strcmp(cmd, "swappiness") == 0) {
		if (val < 0 || val > 200)
			return -ERANGE;
		vm_swappiness = val;
		pr_info("MMOA: vm.swappiness set to %d\n", val);
	} else if (strcmp(cmd, "vfs_cache_pressure") == 0) {
		if (val < 0)
			return -ERANGE;
		vfs_cache_pressure = val;
		pr_info("MMOA: vm.vfs_cache_pressure set to %d\n", val);
	} else if (strcmp(cmd, "frag_threshold") == 0) {
		if (val < 0 || val > 100)
			return -ERANGE;
		mmoa_frag_threshold = val;
		pr_info("MMOA: frag_threshold set to %d%%\n", val);
	} else if (strcmp(cmd, "compact_now") == 0) {
		mmoa_maybe_compact();
		pr_info("MMOA: manual compaction triggered\n");
	} else {
		return -EINVAL;
	}

	return count;
}

static int mmoa_control_show(struct seq_file *m, void *v)
{
	seq_puts(m, "MMOA Control Interface\n");
	seq_puts(m, "Write commands: swappiness <n>, vfs_cache_pressure <n>,\n");
	seq_puts(m, "                frag_threshold <n>, compact_now 1\n");
	return 0;
}

static int mmoa_control_open(struct inode *inode, struct file *file)
{
	return single_open(file, mmoa_control_show, NULL);
}

static const struct proc_ops mmoa_control_ops = {
	.proc_open    = mmoa_control_open,
	.proc_read    = seq_read,
	.proc_write   = mmoa_control_write,
	.proc_lseek   = seq_lseek,
	.proc_release = single_release,
};

/* ------------------------------------------------------------------ */
/* Module init / exit                                                   */
/* ------------------------------------------------------------------ */

static int __init mmoa_init(void)
{
	/* Save originals */
	orig_swappiness         = vm_swappiness;
	orig_vfs_cache_pressure = vfs_cache_pressure;
	orig_min_free_kbytes    = min_free_kbytes;

	/* Apply MMOA tuning */
	vm_swappiness         = mmoa_swappiness;
	vfs_cache_pressure    = mmoa_vfs_cache_pressure;
	min_free_kbytes       = orig_min_free_kbytes * mmoa_min_free_mult;
	setup_per_zone_wmarks();

	pr_info("MMOA: tuned vm.swappiness=%d vfs_cache_pressure=%d min_free_kbytes=%lu\n",
		vm_swappiness, vfs_cache_pressure, min_free_kbytes);

	/* Create /proc entries */
	if (!proc_create("mmoa_stats", 0444, NULL, &mmoa_stats_ops)) {
		pr_err("MMOA: failed to create /proc/mmoa_stats\n");
		return -ENOMEM;
	}
	if (!proc_create("mmoa_control", 0600, NULL, &mmoa_control_ops)) {
		pr_err("MMOA: failed to create /proc/mmoa_control\n");
		remove_proc_entry("mmoa_stats", NULL);
		return -ENOMEM;
	}

	/* Start periodic monitoring */
	INIT_DELAYED_WORK(&mmoa_monitor_work, mmoa_monitor_fn);
	schedule_delayed_work(&mmoa_monitor_work,
			      msecs_to_jiffies(mmoa_monitor_interval * 1000));

	pr_info("MMOA: module loaded — memory optimization active\n");
	return 0;
}

static void __exit mmoa_exit(void)
{
	cancel_delayed_work_sync(&mmoa_monitor_work);

	/* Restore original sysctl values */
	vm_swappiness         = orig_swappiness;
	vfs_cache_pressure    = orig_vfs_cache_pressure;
	min_free_kbytes       = orig_min_free_kbytes;
	setup_per_zone_wmarks();

	remove_proc_entry("mmoa_stats", NULL);
	remove_proc_entry("mmoa_control", NULL);

	pr_info("MMOA: module unloaded — sysctl values restored\n");
}

module_init(mmoa_init);
module_exit(mmoa_exit);
