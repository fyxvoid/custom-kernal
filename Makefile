# SecureKernel — Top-level Makefile
# Builds/loads all four modules and runs benchmarks.

KDIR      ?= /lib/modules/$(shell uname -r)/build
ARCH      ?= x86_64
PROFILE   ?= embedded
KERNEL_SRC ?= /usr/src/linux

.PHONY: all modules load unload reload clean bench help \
        m1-prune m2-build m2-load m3-build m3-load m4-build m4-load

all: modules

# ── Module 1: Kernel Lightening ───────────────────────────────────────────────
m1-prune:
	$(MAKE) -C module1_kernel_lightening \
		KERNEL_SRC=$(KERNEL_SRC) ARCH=$(ARCH) PROFILE=$(PROFILE)

# ── Module 2: Memory Optimization ────────────────────────────────────────────
m2-build:
	$(MAKE) -C module2_memory KDIR=$(KDIR)

m2-load:
	$(MAKE) -C module2_memory load

# ── Module 3: Network Packet Filter ──────────────────────────────────────────
m3-build:
	$(MAKE) -C module3_network KDIR=$(KDIR)

m3-load:
	$(MAKE) -C module3_network load

# ── Module 4: Security LSM ────────────────────────────────────────────────────
m4-build:
	$(MAKE) -C module4_security KDIR=$(KDIR)

m4-load:
	$(MAKE) -C module4_security load

# ── Combined targets ──────────────────────────────────────────────────────────
modules: m2-build m3-build m4-build

load: m2-load m3-load m4-load
	@echo "All modules loaded."
	@lsmod | grep -E "mmoa|rbpf|acm_lsm" || true

unload:
	$(MAKE) -C module4_security unload
	$(MAKE) -C module3_network  unload
	$(MAKE) -C module2_memory   unload

reload: unload load

clean:
	$(MAKE) -C module1_kernel_lightening clean
	$(MAKE) -C module2_memory  clean
	$(MAKE) -C module3_network clean
	$(MAKE) -C module4_security clean
	rm -f benchmarks/results/*.csv

# ── Benchmarks ────────────────────────────────────────────────────────────────
bench:
	@chmod +x benchmarks/run_benchmarks.sh
	@bash benchmarks/run_benchmarks.sh

bench-compare:
	@[[ -n "$(STOCK)" && -n "$(CUSTOM)" ]] || \
		{ echo "Usage: make bench-compare STOCK=<csv> CUSTOM=<csv>"; exit 1; }
	@chmod +x benchmarks/compare_results.sh
	@bash benchmarks/compare_results.sh $(STOCK) $(CUSTOM)

# ── Demo ──────────────────────────────────────────────────────────────────────
demo: load
	@echo ""
	@echo "=== RBPF Demo Rules ==="
	$(MAKE) -C module3_network demo_rules
	@echo ""
	@echo "=== ACM Demo Policy ==="
	$(MAKE) -C module4_security demo_policy
	@echo ""
	@echo "=== MMOA Stats ==="
	cat /proc/mmoa_stats 2>/dev/null || echo "mmoa module not loaded"

help:
	@echo "SecureKernel — Linux Kernel Security & Lightweight Modification"
	@echo ""
	@echo "Targets:"
	@echo "  all         Build all loadable kernel modules (default)"
	@echo "  load        Load all modules into the running kernel"
	@echo "  unload      Unload all modules"
	@echo "  reload      Unload then reload all modules"
	@echo "  clean       Remove build artefacts"
	@echo "  bench       Run benchmark suite"
	@echo "  demo        Load modules and install demo rules/policy"
	@echo "  m1-prune    Run SCPA kernel config pruning (needs kernel src)"
	@echo ""
	@echo "Variables:"
	@echo "  KDIR=$(KDIR)"
	@echo "  ARCH=$(ARCH)"
	@echo "  PROFILE=$(PROFILE)  [embedded|server|desktop|iot]"
	@echo "  KERNEL_SRC=$(KERNEL_SRC)"
