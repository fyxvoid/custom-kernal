// SPDX-License-Identifier: GPL-2.0
/*
 * Module 3: Network Module Modification
 * Rule-Based Packet Filtering Algorithm (RBPF)
 *
 * Implements kernel-level packet filtering via Netfilter hooks.
 * Rules are stored as a priority-ordered linked list in kernel memory
 * and evaluated against each packet's IP/port/protocol attributes.
 *
 * Rule table can be managed at runtime via /proc/rbpf_rules.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/netfilter.h>
#include <linux/netfilter_ipv4.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <linux/icmp.h>
#include <linux/skbuff.h>
#include <linux/list.h>
#include <linux/spinlock.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/inet.h>
#include <linux/string.h>
#include <linux/ktime.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("SecureKernel Team");
MODULE_DESCRIPTION("RBPF: Rule-Based Packet Filtering at Netfilter hooks");
MODULE_VERSION("1.0");

/* Rule actions */
#define RBPF_ACCEPT  0
#define RBPF_DROP    1
#define RBPF_LOG     2

/* Protocol wildcards */
#define RBPF_PROTO_ANY 0xFF

/* Port wildcard (0 = any) */
#define RBPF_PORT_ANY  0

/* Maximum number of rules */
#define RBPF_MAX_RULES 256

/* Maximum proc write buffer */
#define RBPF_PROC_BUF  512

/**
 * struct rbpf_rule - a single filtering rule entry
 * @list:       linked list node
 * @priority:   lower value = higher priority; rules sorted ascending
 * @src_ip:     source IP (network byte order); 0 = any
 * @src_mask:   source netmask (network byte order)
 * @dst_ip:     destination IP (network byte order); 0 = any
 * @dst_mask:   destination netmask (network byte order)
 * @src_port_lo: source port range low (host byte order); 0 = any
 * @src_port_hi: source port range high (host byte order)
 * @dst_port_lo: destination port range low (host byte order)
 * @dst_port_hi: destination port range high (host byte order)
 * @protocol:   IP protocol number; RBPF_PROTO_ANY = any
 * @action:     RBPF_ACCEPT | RBPF_DROP | RBPF_LOG
 * @hit_count:  number of packets matched by this rule
 */
struct rbpf_rule {
	struct list_head list;
	int              priority;
	__be32           src_ip;
	__be32           src_mask;
	__be32           dst_ip;
	__be32           dst_mask;
	u16              src_port_lo;
	u16              src_port_hi;
	u16              dst_port_lo;
	u16              dst_port_hi;
	u8               protocol;
	u8               action;
	u64              hit_count;
};

/* Global rule list and its spinlock */
static LIST_HEAD(rbpf_rules);
static DEFINE_SPINLOCK(rbpf_lock);
static int rbpf_rule_count = 0;

/* Netfilter hook operations */
static struct nf_hook_ops rbpf_hooks[5];

/* Statistics */
static u64 stat_accepted = 0;
static u64 stat_dropped  = 0;
static u64 stat_logged   = 0;

/* ------------------------------------------------------------------ */
/* Rule matching                                                        */
/* ------------------------------------------------------------------ */

static inline bool ip_matches(__be32 pkt_ip, __be32 rule_ip, __be32 rule_mask)
{
	if (rule_ip == 0)
		return true; /* wildcard */
	return (pkt_ip & rule_mask) == (rule_ip & rule_mask);
}

static inline bool port_matches(u16 pkt_port, u16 lo, u16 hi)
{
	if (lo == RBPF_PORT_ANY && hi == RBPF_PORT_ANY)
		return true;
	return pkt_port >= lo && pkt_port <= hi;
}

/**
 * rbpf_evaluate - evaluate a packet against the rule table
 *
 * Returns NF_ACCEPT or NF_DROP. Logs if rule action is LOG.
 * Must be called with rbpf_lock held (read side sufficient — we use spinlock).
 */
static unsigned int rbpf_evaluate(struct sk_buff *skb, int hooknum)
{
	struct iphdr  *iph;
	struct tcphdr *tcph = NULL;
	struct udphdr *udph = NULL;
	u16 sport = 0, dport = 0;
	u8  proto;
	struct rbpf_rule *rule;
	unsigned long flags;

	iph = ip_hdr(skb);
	if (!iph)
		return NF_ACCEPT;

	proto = iph->protocol;

	if (proto == IPPROTO_TCP) {
		tcph = tcp_hdr(skb);
		if (tcph) {
			sport = ntohs(tcph->source);
			dport = ntohs(tcph->dest);
		}
	} else if (proto == IPPROTO_UDP) {
		udph = udp_hdr(skb);
		if (udph) {
			sport = ntohs(udph->source);
			dport = ntohs(udph->dest);
		}
	}

	spin_lock_irqsave(&rbpf_lock, flags);

	list_for_each_entry(rule, &rbpf_rules, list) {
		/* Protocol match */
		if (rule->protocol != RBPF_PROTO_ANY && rule->protocol != proto)
			continue;

		/* IP match */
		if (!ip_matches(iph->saddr, rule->src_ip, rule->src_mask))
			continue;
		if (!ip_matches(iph->daddr, rule->dst_ip, rule->dst_mask))
			continue;

		/* Port match (only meaningful for TCP/UDP) */
		if (proto == IPPROTO_TCP || proto == IPPROTO_UDP) {
			if (!port_matches(sport, rule->src_port_lo, rule->src_port_hi))
				continue;
			if (!port_matches(dport, rule->dst_port_lo, rule->dst_port_hi))
				continue;
		}

		/* Matched */
		rule->hit_count++;

		if (rule->action == RBPF_LOG) {
			stat_logged++;
			pr_info("RBPF[hook=%d] LOG src=%pI4:%u dst=%pI4:%u proto=%u\n",
				hooknum,
				&iph->saddr, sport,
				&iph->daddr, dport,
				proto);
			/* LOG falls through to ACCEPT */
			stat_accepted++;
			spin_unlock_irqrestore(&rbpf_lock, flags);
			return NF_ACCEPT;
		}

		if (rule->action == RBPF_DROP) {
			stat_dropped++;
			spin_unlock_irqrestore(&rbpf_lock, flags);
			return NF_DROP;
		}

		/* RBPF_ACCEPT */
		stat_accepted++;
		spin_unlock_irqrestore(&rbpf_lock, flags);
		return NF_ACCEPT;
	}

	/* Default policy: DROP (hardened configuration) */
	stat_dropped++;
	spin_unlock_irqrestore(&rbpf_lock, flags);
	return NF_DROP;
}

/* ------------------------------------------------------------------ */
/* Netfilter hook callbacks                                             */
/* ------------------------------------------------------------------ */

static unsigned int rbpf_hook_pre_routing(void *priv,
					  struct sk_buff *skb,
					  const struct nf_hook_state *state)
{
	return rbpf_evaluate(skb, NF_INET_PRE_ROUTING);
}

static unsigned int rbpf_hook_local_in(void *priv,
					struct sk_buff *skb,
					const struct nf_hook_state *state)
{
	return rbpf_evaluate(skb, NF_INET_LOCAL_IN);
}

static unsigned int rbpf_hook_forward(void *priv,
				      struct sk_buff *skb,
				      const struct nf_hook_state *state)
{
	return rbpf_evaluate(skb, NF_INET_FORWARD);
}

static unsigned int rbpf_hook_local_out(void *priv,
					 struct sk_buff *skb,
					 const struct nf_hook_state *state)
{
	return rbpf_evaluate(skb, NF_INET_LOCAL_OUT);
}

static unsigned int rbpf_hook_post_routing(void *priv,
					   struct sk_buff *skb,
					   const struct nf_hook_state *state)
{
	return rbpf_evaluate(skb, NF_INET_POST_ROUTING);
}

/* ------------------------------------------------------------------ */
/* /proc interface for rule management                                  */
/* ------------------------------------------------------------------ */

/*
 * Rule format for writing via /proc/rbpf_rules:
 *   ADD <priority> <src_ip/mask> <dst_ip/mask> <sport_lo-sport_hi>
 *       <dport_lo-dport_hi> <proto> <action>
 *   DEL <priority>
 *   FLUSH
 *
 * Example:
 *   echo "ADD 10 192.168.1.0/24 0.0.0.0/0 0-0 80-80 tcp accept" \
 *       > /proc/rbpf_rules
 *   echo "ADD 5 10.0.0.1/32 0.0.0.0/0 0-0 0-0 any drop" \
 *       > /proc/rbpf_rules
 */

static void rbpf_insert_rule_sorted(struct rbpf_rule *new_rule)
{
	struct rbpf_rule *cur;

	list_for_each_entry(cur, &rbpf_rules, list) {
		if (new_rule->priority < cur->priority) {
			list_add_tail(&new_rule->list, &cur->list);
			return;
		}
	}
	list_add_tail(&new_rule->list, &rbpf_rules);
}

static int rbpf_parse_ip_mask(const char *str, __be32 *ip, __be32 *mask)
{
	char ip_str[18];
	const char *slash;
	int prefix_len = 32;
	u32 mask_val;
	int ret;

	slash = strchr(str, '/');
	if (slash) {
		size_t len = slash - str;
		if (len >= sizeof(ip_str))
			return -EINVAL;
		memcpy(ip_str, str, len);
		ip_str[len] = '\0';
		ret = kstrtoint(slash + 1, 10, &prefix_len);
		if (ret || prefix_len < 0 || prefix_len > 32)
			return -EINVAL;
	} else {
		strscpy(ip_str, str, sizeof(ip_str));
	}

	if (strcmp(ip_str, "0.0.0.0") == 0 || strcmp(ip_str, "any") == 0) {
		*ip = 0;
		*mask = 0;
		return 0;
	}

	ret = in4_pton(ip_str, -1, (u8 *)ip, -1, NULL);
	if (!ret)
		return -EINVAL;

	if (prefix_len == 0)
		mask_val = 0;
	else
		mask_val = htonl(~((1U << (32 - prefix_len)) - 1));
	*mask = mask_val;
	return 0;
}

static ssize_t rbpf_proc_write(struct file *file, const char __user *buf,
				size_t count, loff_t *ppos)
{
	char kbuf[RBPF_PROC_BUF];
	char cmd[16], src_str[24], dst_str[24], proto_str[8], action_str[8];
	char sport_str[12], dport_str[12];
	struct rbpf_rule *rule, *tmp;
	unsigned long flags;
	int priority, ret;
	u16 sport_lo, sport_hi, dport_lo, dport_hi;

	if (count >= RBPF_PROC_BUF)
		return -EINVAL;
	if (copy_from_user(kbuf, buf, count))
		return -EFAULT;
	kbuf[count] = '\0';

	/* Strip trailing newline */
	if (count > 0 && kbuf[count - 1] == '\n')
		kbuf[count - 1] = '\0';

	if (sscanf(kbuf, "%15s", cmd) != 1)
		return -EINVAL;

	if (strcasecmp(cmd, "FLUSH") == 0) {
		spin_lock_irqsave(&rbpf_lock, flags);
		list_for_each_entry_safe(rule, tmp, &rbpf_rules, list) {
			list_del(&rule->list);
			kfree(rule);
		}
		rbpf_rule_count = 0;
		spin_unlock_irqrestore(&rbpf_lock, flags);
		pr_info("RBPF: rule table flushed\n");
		return count;
	}

	if (strcasecmp(cmd, "DEL") == 0) {
		if (sscanf(kbuf, "%*s %d", &priority) != 1)
			return -EINVAL;
		spin_lock_irqsave(&rbpf_lock, flags);
		list_for_each_entry_safe(rule, tmp, &rbpf_rules, list) {
			if (rule->priority == priority) {
				list_del(&rule->list);
				kfree(rule);
				rbpf_rule_count--;
				break;
			}
		}
		spin_unlock_irqrestore(&rbpf_lock, flags);
		return count;
	}

	if (strcasecmp(cmd, "ADD") == 0) {
		if (rbpf_rule_count >= RBPF_MAX_RULES)
			return -ENOSPC;

		ret = sscanf(kbuf, "%*s %d %23s %23s %11s %11s %7s %7s",
			     &priority, src_str, dst_str,
			     sport_str, dport_str, proto_str, action_str);
		if (ret != 7)
			return -EINVAL;

		rule = kzalloc(sizeof(*rule), GFP_KERNEL);
		if (!rule)
			return -ENOMEM;

		rule->priority = priority;

		if (rbpf_parse_ip_mask(src_str, &rule->src_ip, &rule->src_mask)) {
			kfree(rule);
			return -EINVAL;
		}
		if (rbpf_parse_ip_mask(dst_str, &rule->dst_ip, &rule->dst_mask)) {
			kfree(rule);
			return -EINVAL;
		}

		/* Parse port ranges: lo-hi */
		if (sscanf(sport_str, "%hu-%hu", &sport_lo, &sport_hi) != 2) {
			kfree(rule);
			return -EINVAL;
		}
		rule->src_port_lo = sport_lo;
		rule->src_port_hi = sport_hi;

		if (sscanf(dport_str, "%hu-%hu", &dport_lo, &dport_hi) != 2) {
			kfree(rule);
			return -EINVAL;
		}
		rule->dst_port_lo = dport_lo;
		rule->dst_port_hi = dport_hi;

		if (strcasecmp(proto_str, "tcp") == 0)
			rule->protocol = IPPROTO_TCP;
		else if (strcasecmp(proto_str, "udp") == 0)
			rule->protocol = IPPROTO_UDP;
		else if (strcasecmp(proto_str, "icmp") == 0)
			rule->protocol = IPPROTO_ICMP;
		else
			rule->protocol = RBPF_PROTO_ANY;

		if (strcasecmp(action_str, "accept") == 0)
			rule->action = RBPF_ACCEPT;
		else if (strcasecmp(action_str, "log") == 0)
			rule->action = RBPF_LOG;
		else
			rule->action = RBPF_DROP;

		spin_lock_irqsave(&rbpf_lock, flags);
		rbpf_insert_rule_sorted(rule);
		rbpf_rule_count++;
		spin_unlock_irqrestore(&rbpf_lock, flags);

		pr_info("RBPF: rule added priority=%d action=%s\n",
			priority, action_str);
		return count;
	}

	return -EINVAL;
}

static int rbpf_proc_show(struct seq_file *m, void *v)
{
	struct rbpf_rule *rule;
	unsigned long flags;
	const char *action_str;

	seq_printf(m, "RBPF Rule Table  rules=%d  accepted=%llu  dropped=%llu  logged=%llu\n",
		   rbpf_rule_count, stat_accepted, stat_dropped, stat_logged);
	seq_puts(m, "PRIO  SRC_IP/MASK          DST_IP/MASK          SPORT        DPORT        PROTO   ACTION  HITS\n");
	seq_puts(m, "----  -------------------  -------------------  -----------  -----------  ------  ------  ----\n");

	spin_lock_irqsave(&rbpf_lock, flags);
	list_for_each_entry(rule, &rbpf_rules, list) {
		switch (rule->action) {
		case RBPF_ACCEPT: action_str = "ACCEPT"; break;
		case RBPF_DROP:   action_str = "DROP";   break;
		case RBPF_LOG:    action_str = "LOG";    break;
		default:          action_str = "?";
		}
		seq_printf(m, "%-5d %-20pI4 %-20pI4 %5u-%-5u %5u-%-5u %-7u %-7s %llu\n",
			   rule->priority,
			   &rule->src_ip, &rule->dst_ip,
			   rule->src_port_lo, rule->src_port_hi,
			   rule->dst_port_lo, rule->dst_port_hi,
			   rule->protocol,
			   action_str,
			   rule->hit_count);
	}
	spin_unlock_irqrestore(&rbpf_lock, flags);
	return 0;
}

static int rbpf_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, rbpf_proc_show, NULL);
}

static const struct proc_ops rbpf_proc_ops = {
	.proc_open    = rbpf_proc_open,
	.proc_read    = seq_read,
	.proc_write   = rbpf_proc_write,
	.proc_lseek   = seq_lseek,
	.proc_release = single_release,
};

/* ------------------------------------------------------------------ */
/* Module init / exit                                                   */
/* ------------------------------------------------------------------ */

static void rbpf_install_default_rules(void)
{
	/*
	 * Default hardened policy:
	 *   Allow loopback (127.0.0.1/8) traffic unconditionally.
	 *   Allow established TCP on high ports (example allowlist).
	 *   Drop everything else (handled by default-drop in rbpf_evaluate).
	 *
	 * Users should add their own rules via /proc/rbpf_rules.
	 */
	struct rbpf_rule *lo_rule;
	unsigned long flags;

	lo_rule = kzalloc(sizeof(*lo_rule), GFP_KERNEL);
	if (!lo_rule)
		return;

	lo_rule->priority    = 1;
	lo_rule->src_ip      = htonl(0x7F000000); /* 127.0.0.0 */
	lo_rule->src_mask    = htonl(0xFF000000); /* /8 */
	lo_rule->dst_ip      = 0;
	lo_rule->dst_mask    = 0;
	lo_rule->src_port_lo = 0;
	lo_rule->src_port_hi = 0;
	lo_rule->dst_port_lo = 0;
	lo_rule->dst_port_hi = 0;
	lo_rule->protocol    = RBPF_PROTO_ANY;
	lo_rule->action      = RBPF_ACCEPT;

	spin_lock_irqsave(&rbpf_lock, flags);
	rbpf_insert_rule_sorted(lo_rule);
	rbpf_rule_count++;
	spin_unlock_irqrestore(&rbpf_lock, flags);

	pr_info("RBPF: default loopback ACCEPT rule installed\n");
}

static int __init rbpf_init(void)
{
	int ret;

	/* Install default rules */
	rbpf_install_default_rules();

	/* Register /proc entry */
	if (!proc_create("rbpf_rules", 0644, NULL, &rbpf_proc_ops)) {
		pr_err("RBPF: failed to create /proc/rbpf_rules\n");
		return -ENOMEM;
	}

	/* Register Netfilter hooks */
	rbpf_hooks[0].hook     = rbpf_hook_pre_routing;
	rbpf_hooks[0].hooknum  = NF_INET_PRE_ROUTING;
	rbpf_hooks[0].pf       = PF_INET;
	rbpf_hooks[0].priority = NF_IP_PRI_FIRST;

	rbpf_hooks[1].hook     = rbpf_hook_local_in;
	rbpf_hooks[1].hooknum  = NF_INET_LOCAL_IN;
	rbpf_hooks[1].pf       = PF_INET;
	rbpf_hooks[1].priority = NF_IP_PRI_FIRST;

	rbpf_hooks[2].hook     = rbpf_hook_forward;
	rbpf_hooks[2].hooknum  = NF_INET_FORWARD;
	rbpf_hooks[2].pf       = PF_INET;
	rbpf_hooks[2].priority = NF_IP_PRI_FIRST;

	rbpf_hooks[3].hook     = rbpf_hook_local_out;
	rbpf_hooks[3].hooknum  = NF_INET_LOCAL_OUT;
	rbpf_hooks[3].pf       = PF_INET;
	rbpf_hooks[3].priority = NF_IP_PRI_FIRST;

	rbpf_hooks[4].hook     = rbpf_hook_post_routing;
	rbpf_hooks[4].hooknum  = NF_INET_POST_ROUTING;
	rbpf_hooks[4].pf       = PF_INET;
	rbpf_hooks[4].priority = NF_IP_PRI_LAST;

	ret = nf_register_net_hooks(&init_net, rbpf_hooks, ARRAY_SIZE(rbpf_hooks));
	if (ret) {
		pr_err("RBPF: failed to register Netfilter hooks: %d\n", ret);
		remove_proc_entry("rbpf_rules", NULL);
		return ret;
	}

	pr_info("RBPF: module loaded — kernel-level packet filtering active\n");
	return 0;
}

static void __exit rbpf_exit(void)
{
	struct rbpf_rule *rule, *tmp;
	unsigned long flags;

	nf_unregister_net_hooks(&init_net, rbpf_hooks, ARRAY_SIZE(rbpf_hooks));
	remove_proc_entry("rbpf_rules", NULL);

	spin_lock_irqsave(&rbpf_lock, flags);
	list_for_each_entry_safe(rule, tmp, &rbpf_rules, list) {
		list_del(&rule->list);
		kfree(rule);
	}
	spin_unlock_irqrestore(&rbpf_lock, flags);

	pr_info("RBPF: module unloaded\n");
}

module_init(rbpf_init);
module_exit(rbpf_exit);
