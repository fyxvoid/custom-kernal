// SPDX-License-Identifier: GPL-2.0
/*
 * Module 4: Security Module Modification
 * Access Control Mechanism (ACM) — Custom Linux Security Module
 *
 * Implements Mandatory Access Control via the LSM framework.
 * Security labels are assigned to processes and kernel objects.
 * Policy rules define which (subject_label, object_label, operation)
 * triples are permitted.
 *
 * Policy is loaded/updated at runtime via /proc/acm_policy.
 * All denied operations are logged to the kernel ring buffer.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/security.h>
#include <linux/lsm_hooks.h>
#include <linux/cred.h>
#include <linux/fs.h>
#include <linux/file.h>
#include <linux/path.h>
#include <linux/dcache.h>
#include <linux/socket.h>
#include <linux/net.h>
#include <linux/in.h>
#include <linux/inet.h>
#include <linux/binfmts.h>
#include <linux/mm.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/list.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/ptrace.h>
#include <linux/string.h>
#include <linux/atomic.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("SecureKernel Team");
MODULE_DESCRIPTION("ACM: Mandatory Access Control LSM");
MODULE_VERSION("1.0");

/* ------------------------------------------------------------------ */
/* Labels and operations                                                */
/* ------------------------------------------------------------------ */

#define ACM_LABEL_LEN     32
#define ACM_MAX_LABELS    64
#define ACM_MAX_RULES     512
#define ACM_PROC_BUF      512

/* Default label assigned to unlabelled subjects/objects */
#define ACM_LABEL_DEFAULT "default"
#define ACM_LABEL_KERNEL  "kernel"
#define ACM_LABEL_TRUSTED "trusted"

/* Operation bit flags */
#define ACM_OP_READ      BIT(0)
#define ACM_OP_WRITE     BIT(1)
#define ACM_OP_EXEC      BIT(2)
#define ACM_OP_CREATE    BIT(3)
#define ACM_OP_NET       BIT(4)
#define ACM_OP_SETUID    BIT(5)
#define ACM_OP_PTRACE    BIT(6)
#define ACM_OP_MMAP_EXEC BIT(7)

/* ------------------------------------------------------------------ */
/* Policy structures                                                    */
/* ------------------------------------------------------------------ */

/**
 * struct acm_label - intern table entry mapping a name to an ID
 */
struct acm_label {
	char name[ACM_LABEL_LEN];
	int  id;
};

/**
 * struct acm_rule - a single MAC policy rule
 * @list:       linked list node
 * @subj_id:    subject label id (-1 = any)
 * @obj_id:     object label id  (-1 = any)
 * @ops_allow:  bitmask of permitted operations
 * @deny_count: count of denied requests matched by this rule
 */
struct acm_rule {
	struct list_head list;
	int  subj_id;
	int  obj_id;
	u32  ops_allow;
	u64  deny_count;
	u64  allow_count;
};

/* Label intern table */
static struct acm_label acm_labels[ACM_MAX_LABELS];
static int acm_label_count = 0;

/* Policy rule list */
static LIST_HEAD(acm_rules);
static DEFINE_SPINLOCK(acm_lock);
static int acm_rule_count = 0;

/* Audit statistics */
static atomic64_t acm_stat_allow = ATOMIC64_INIT(0);
static atomic64_t acm_stat_deny  = ATOMIC64_INIT(0);

/* ------------------------------------------------------------------ */
/* Label internment                                                     */
/* ------------------------------------------------------------------ */

static int acm_label_find(const char *name)
{
	int i;
	for (i = 0; i < acm_label_count; i++)
		if (strncmp(acm_labels[i].name, name, ACM_LABEL_LEN) == 0)
			return acm_labels[i].id;
	return -1;
}

static int acm_label_intern(const char *name)
{
	int id = acm_label_find(name);
	if (id >= 0)
		return id;
	if (acm_label_count >= ACM_MAX_LABELS)
		return -ENOSPC;
	id = acm_label_count++;
	strscpy(acm_labels[id].name, name, ACM_LABEL_LEN);
	acm_labels[id].id = id;
	return id;
}

static const char *acm_label_name(int id)
{
	if (id < 0 || id >= acm_label_count)
		return "<unknown>";
	return acm_labels[id].name;
}

/* ------------------------------------------------------------------ */
/* Per-task security blob                                               */
/* ------------------------------------------------------------------ */

struct acm_task_sec {
	int label_id; /* subject label for this task */
};

/* Blob sizes registered with the LSM infrastructure */
static struct lsm_blob_sizes acm_blob_sizes __lsm_ro_after_init = {
	.lbs_cred = sizeof(struct acm_task_sec),
};

static inline struct acm_task_sec *acm_cred(const struct cred *cred)
{
	return cred->security + acm_blob_sizes.lbs_cred;
}

/* ------------------------------------------------------------------ */
/* Policy evaluation                                                    */
/* ------------------------------------------------------------------ */

/**
 * acm_check - evaluate access request against policy
 * @subj_id: subject's label id
 * @obj_id:  target object's label id
 * @op:      operation bit (ACM_OP_*)
 * @desc:    human-readable description for audit log
 *
 * Returns 0 (allow) or -EACCES (deny).
 */
static int acm_check(int subj_id, int obj_id, u32 op, const char *desc)
{
	struct acm_rule *rule;
	unsigned long flags;
	int permit = 0;

	spin_lock_irqsave(&acm_lock, flags);
	list_for_each_entry(rule, &acm_rules, list) {
		bool subj_match = (rule->subj_id == -1 || rule->subj_id == subj_id);
		bool obj_match  = (rule->obj_id  == -1 || rule->obj_id  == obj_id);
		if (subj_match && obj_match && (rule->ops_allow & op)) {
			rule->allow_count++;
			permit = 1;
			break;
		}
	}

	if (!permit) {
		/* Find deny rule to update counter (best-effort) */
		list_for_each_entry(rule, &acm_rules, list) {
			bool sm = (rule->subj_id == -1 || rule->subj_id == subj_id);
			bool om = (rule->obj_id  == -1 || rule->obj_id  == obj_id);
			if (sm && om) {
				rule->deny_count++;
				break;
			}
		}
	}
	spin_unlock_irqrestore(&acm_lock, flags);

	if (!permit) {
		atomic64_inc(&acm_stat_deny);
		pr_warn("ACM DENY pid=%d subj=%s obj=%s op=%s\n",
			current->pid,
			acm_label_name(subj_id),
			acm_label_name(obj_id),
			desc);
		return -EACCES;
	}

	atomic64_inc(&acm_stat_allow);
	return 0;
}

static int acm_current_label(void)
{
	const struct cred *cred = current_cred();
	struct acm_task_sec *sec;
	int default_id;

	if (!cred || !cred->security)
		goto fallback;

	sec = acm_cred(cred);
	if (sec->label_id >= 0)
		return sec->label_id;

fallback:
	default_id = acm_label_find(ACM_LABEL_DEFAULT);
	return (default_id >= 0) ? default_id : 0;
}

/* ------------------------------------------------------------------ */
/* LSM hooks                                                            */
/* ------------------------------------------------------------------ */

static int acm_cred_alloc_blank(struct cred *cred, gfp_t gfp)
{
	struct acm_task_sec *sec = acm_cred(cred);
	sec->label_id = acm_label_find(ACM_LABEL_DEFAULT);
	if (sec->label_id < 0)
		sec->label_id = 0;
	return 0;
}

static int acm_cred_prepare(struct cred *new, const struct cred *old, gfp_t gfp)
{
	struct acm_task_sec *old_sec = acm_cred(old);
	struct acm_task_sec *new_sec = acm_cred(new);
	new_sec->label_id = old_sec->label_id;
	return 0;
}

/* Hook: file open */
static int acm_file_open(struct file *file)
{
	int subj_id = acm_current_label();
	int obj_id  = acm_label_find(ACM_LABEL_DEFAULT);
	u32 op;

	if (obj_id < 0)
		obj_id = 0;

	op = (file->f_mode & FMODE_WRITE) ? ACM_OP_WRITE : ACM_OP_READ;
	return acm_check(subj_id, obj_id, op, "file_open");
}

/* Hook: inode create */
static int acm_inode_create(struct inode *dir, struct dentry *dentry, umode_t mode)
{
	int subj_id = acm_current_label();
	int obj_id  = acm_label_find(ACM_LABEL_DEFAULT);

	if (obj_id < 0)
		obj_id = 0;
	return acm_check(subj_id, obj_id, ACM_OP_CREATE, "inode_create");
}

/* Hook: socket create */
static int acm_socket_create(int family, int type, int protocol, int kern)
{
	int subj_id;

	if (kern)
		return 0; /* kernel sockets always allowed */

	subj_id = acm_current_label();
	return acm_check(subj_id, acm_label_find(ACM_LABEL_KERNEL),
			 ACM_OP_NET, "socket_create");
}

/* Hook: socket connect */
static int acm_socket_connect(struct socket *sock, struct sockaddr *address, int addrlen)
{
	int subj_id = acm_current_label();
	return acm_check(subj_id, acm_label_find(ACM_LABEL_KERNEL),
			 ACM_OP_NET, "socket_connect");
}

/* Hook: setuid (task_fix_setuid) */
static int acm_task_fix_setuid(struct cred *new, const struct cred *old, int flags)
{
	int subj_id;

	/* Allow if already root or transitioning within same uid */
	if (old->uid.val == 0 || old->uid.val == new->uid.val)
		return 0;

	subj_id = acm_label_find(ACM_LABEL_DEFAULT);
	if (subj_id < 0)
		subj_id = 0;
	return acm_check(subj_id, acm_label_find(ACM_LABEL_KERNEL),
			 ACM_OP_SETUID, "task_fix_setuid");
}

/* Hook: mmap file (prevent executable mmap of untrusted sources) */
static int acm_mmap_file(struct file *file, unsigned long reqprot,
			  unsigned long prot, unsigned long flags)
{
	int subj_id;

	if (!(prot & PROT_EXEC) || !file)
		return 0;

	subj_id = acm_current_label();
	return acm_check(subj_id, acm_label_find(ACM_LABEL_DEFAULT),
			 ACM_OP_MMAP_EXEC, "mmap_file_exec");
}

/* Hook: ptrace access */
static int acm_ptrace_access_check(struct task_struct *child, unsigned int mode)
{
	int subj_id = acm_current_label();
	return acm_check(subj_id, acm_label_find(ACM_LABEL_DEFAULT),
			 ACM_OP_PTRACE, "ptrace_access");
}

/* ------------------------------------------------------------------ */
/* LSM registration                                                     */
/* ------------------------------------------------------------------ */

static struct security_hook_list acm_hooks[] __lsm_ro_after_init = {
	LSM_HOOK_INIT(cred_alloc_blank,     acm_cred_alloc_blank),
	LSM_HOOK_INIT(cred_prepare,         acm_cred_prepare),
	LSM_HOOK_INIT(file_open,            acm_file_open),
	LSM_HOOK_INIT(inode_create,         acm_inode_create),
	LSM_HOOK_INIT(socket_create,        acm_socket_create),
	LSM_HOOK_INIT(socket_connect,       acm_socket_connect),
	LSM_HOOK_INIT(task_fix_setuid,      acm_task_fix_setuid),
	LSM_HOOK_INIT(mmap_file,            acm_mmap_file),
	LSM_HOOK_INIT(ptrace_access_check,  acm_ptrace_access_check),
};

/* ------------------------------------------------------------------ */
/* /proc policy interface                                               */
/* ------------------------------------------------------------------ */

/*
 * Policy file format (written to /proc/acm_policy):
 *
 *   LABEL <name>
 *     — intern a label name (creates it if not present)
 *
 *   ALLOW <subj_label|any> <obj_label|any> <op1>[,<op2>,...]
 *     — add a rule permitting listed operations
 *     ops: read, write, exec, create, net, setuid, ptrace, mmap_exec
 *
 *   FLUSH
 *     — remove all rules
 *
 *   SETLABEL <pid> <label>
 *     — assign a security label to a running process (requires CAP_SYS_ADMIN)
 */

static u32 acm_parse_ops(const char *ops_str)
{
	u32 ops = 0;
	if (strstr(ops_str, "read"))      ops |= ACM_OP_READ;
	if (strstr(ops_str, "write"))     ops |= ACM_OP_WRITE;
	if (strstr(ops_str, "exec"))      ops |= ACM_OP_EXEC;
	if (strstr(ops_str, "create"))    ops |= ACM_OP_CREATE;
	if (strstr(ops_str, "net"))       ops |= ACM_OP_NET;
	if (strstr(ops_str, "setuid"))    ops |= ACM_OP_SETUID;
	if (strstr(ops_str, "ptrace"))    ops |= ACM_OP_PTRACE;
	if (strstr(ops_str, "mmap_exec")) ops |= ACM_OP_MMAP_EXEC;
	if (strstr(ops_str, "all"))       ops  = 0xFFFFFFFF;
	return ops;
}

static ssize_t acm_proc_write(struct file *file, const char __user *buf,
			       size_t count, loff_t *ppos)
{
	char kbuf[ACM_PROC_BUF];
	char cmd[16], subj_str[ACM_LABEL_LEN], obj_str[ACM_LABEL_LEN], ops_str[128];
	struct acm_rule *rule, *tmp;
	unsigned long flags;
	int subj_id, obj_id;
	u32 ops;

	if (!capable(CAP_SYS_ADMIN))
		return -EPERM;
	if (count >= ACM_PROC_BUF)
		return -EINVAL;
	if (copy_from_user(kbuf, buf, count))
		return -EFAULT;
	kbuf[count] = '\0';
	if (count > 0 && kbuf[count - 1] == '\n')
		kbuf[count - 1] = '\0';

	if (sscanf(kbuf, "%15s", cmd) != 1)
		return -EINVAL;

	if (strcasecmp(cmd, "FLUSH") == 0) {
		spin_lock_irqsave(&acm_lock, flags);
		list_for_each_entry_safe(rule, tmp, &acm_rules, list) {
			list_del(&rule->list);
			kfree(rule);
		}
		acm_rule_count = 0;
		spin_unlock_irqrestore(&acm_lock, flags);
		pr_info("ACM: policy flushed\n");
		return count;
	}

	if (strcasecmp(cmd, "LABEL") == 0) {
		if (sscanf(kbuf, "%*s %31s", subj_str) != 1)
			return -EINVAL;
		spin_lock_irqsave(&acm_lock, flags);
		acm_label_intern(subj_str);
		spin_unlock_irqrestore(&acm_lock, flags);
		return count;
	}

	if (strcasecmp(cmd, "ALLOW") == 0) {
		if (acm_rule_count >= ACM_MAX_RULES)
			return -ENOSPC;
		if (sscanf(kbuf, "%*s %31s %31s %127[^\n]",
			   subj_str, obj_str, ops_str) != 3)
			return -EINVAL;

		rule = kzalloc(sizeof(*rule), GFP_KERNEL);
		if (!rule)
			return -ENOMEM;

		spin_lock_irqsave(&acm_lock, flags);
		rule->subj_id  = (strcasecmp(subj_str, "any") == 0) ? -1
				  : acm_label_intern(subj_str);
		rule->obj_id   = (strcasecmp(obj_str, "any") == 0) ? -1
				  : acm_label_intern(obj_str);
		rule->ops_allow = acm_parse_ops(ops_str);
		list_add_tail(&rule->list, &acm_rules);
		acm_rule_count++;
		spin_unlock_irqrestore(&acm_lock, flags);

		pr_info("ACM: ALLOW %s -> %s ops=0x%x\n",
			subj_str, obj_str, rule->ops_allow);
		return count;
	}

	return -EINVAL;
}

static int acm_proc_show(struct seq_file *m, void *v)
{
	struct acm_rule *rule;
	unsigned long flags;
	int i;

	seq_printf(m, "ACM Policy  rules=%d  allowed=%lld  denied=%lld\n",
		   acm_rule_count,
		   atomic64_read(&acm_stat_allow),
		   atomic64_read(&acm_stat_deny));

	seq_puts(m, "\nLabels:\n");
	for (i = 0; i < acm_label_count; i++)
		seq_printf(m, "  [%d] %s\n", i, acm_labels[i].name);

	seq_puts(m, "\nRules (SUBJ -> OBJ : OPS_ALLOW : allows : denies):\n");
	spin_lock_irqsave(&acm_lock, flags);
	list_for_each_entry(rule, &acm_rules, list) {
		seq_printf(m, "  %-16s -> %-16s : 0x%08x : %llu : %llu\n",
			   (rule->subj_id == -1) ? "any" : acm_label_name(rule->subj_id),
			   (rule->obj_id  == -1) ? "any" : acm_label_name(rule->obj_id),
			   rule->ops_allow,
			   rule->allow_count,
			   rule->deny_count);
	}
	spin_unlock_irqrestore(&acm_lock, flags);
	return 0;
}

static int acm_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, acm_proc_show, NULL);
}

static const struct proc_ops acm_proc_ops = {
	.proc_open    = acm_proc_open,
	.proc_read    = seq_read,
	.proc_write   = acm_proc_write,
	.proc_lseek   = seq_lseek,
	.proc_release = single_release,
};

/* ------------------------------------------------------------------ */
/* Default policy                                                       */
/* ------------------------------------------------------------------ */

static void acm_load_default_policy(void)
{
	struct acm_rule *rule;
	int trusted_id, default_id, kernel_id;
	unsigned long flags;

	spin_lock_irqsave(&acm_lock, flags);
	trusted_id = acm_label_intern(ACM_LABEL_TRUSTED);
	default_id = acm_label_intern(ACM_LABEL_DEFAULT);
	kernel_id  = acm_label_intern(ACM_LABEL_KERNEL);
	spin_unlock_irqrestore(&acm_lock, flags);

	/* trusted processes may do everything */
	rule = kzalloc(sizeof(*rule), GFP_KERNEL);
	if (rule) {
		rule->subj_id   = trusted_id;
		rule->obj_id    = -1; /* any object */
		rule->ops_allow = 0xFFFFFFFF;
		spin_lock_irqsave(&acm_lock, flags);
		list_add_tail(&rule->list, &acm_rules);
		acm_rule_count++;
		spin_unlock_irqrestore(&acm_lock, flags);
	}

	/* default processes may read/write/exec their own objects */
	rule = kzalloc(sizeof(*rule), GFP_KERNEL);
	if (rule) {
		rule->subj_id   = default_id;
		rule->obj_id    = default_id;
		rule->ops_allow = ACM_OP_READ | ACM_OP_WRITE | ACM_OP_EXEC | ACM_OP_MMAP_EXEC;
		spin_lock_irqsave(&acm_lock, flags);
		list_add_tail(&rule->list, &acm_rules);
		acm_rule_count++;
		spin_unlock_irqrestore(&acm_lock, flags);
	}

	/* default processes may create network sockets */
	rule = kzalloc(sizeof(*rule), GFP_KERNEL);
	if (rule) {
		rule->subj_id   = default_id;
		rule->obj_id    = kernel_id;
		rule->ops_allow = ACM_OP_NET;
		spin_lock_irqsave(&acm_lock, flags);
		list_add_tail(&rule->list, &acm_rules);
		acm_rule_count++;
		spin_unlock_irqrestore(&acm_lock, flags);
	}

	pr_info("ACM: default policy loaded (%d rules)\n", acm_rule_count);
}

/* ------------------------------------------------------------------ */
/* Module init / exit                                                   */
/* ------------------------------------------------------------------ */

static int __init acm_init(void)
{
	acm_load_default_policy();

	security_add_hooks(acm_hooks, ARRAY_SIZE(acm_hooks), "acm");

	if (!proc_create("acm_policy", 0600, NULL, &acm_proc_ops)) {
		pr_err("ACM: failed to create /proc/acm_policy\n");
		return -ENOMEM;
	}

	pr_info("ACM: LSM loaded — Mandatory Access Control active\n");
	return 0;
}

static void __exit acm_exit(void)
{
	struct acm_rule *rule, *tmp;
	unsigned long flags;

	remove_proc_entry("acm_policy", NULL);

	spin_lock_irqsave(&acm_lock, flags);
	list_for_each_entry_safe(rule, tmp, &acm_rules, list) {
		list_del(&rule->list);
		kfree(rule);
	}
	spin_unlock_irqrestore(&acm_lock, flags);

	pr_info("ACM: LSM unloaded\n");
}

module_init(acm_init);
module_exit(acm_exit);
