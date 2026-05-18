KERNEL_SRC ?= /usr/src/linux
ARCH       ?= x86_64
PROFILE    ?= embedded
OUTPUT     ?= $(CURDIR)/hardened.config

.PHONY: all prune compile clean help

all: prune

prune:
	@chmod +x scpa.sh
	@./scpa.sh \
		--kernel-src "$(KERNEL_SRC)" \
		--arch "$(ARCH)" \
		--profile "$(PROFILE)" \
		--output "$(OUTPUT)"

dry-run:
	@chmod +x scpa.sh
	@./scpa.sh \
		--kernel-src "$(KERNEL_SRC)" \
		--arch "$(ARCH)" \
		--profile "$(PROFILE)" \
		--output "$(OUTPUT)" \
		--dry-run

compile:
	@[[ -f "$(OUTPUT)" ]] || { echo "Run 'make prune' first"; exit 1; }
	cp "$(OUTPUT)" "$(KERNEL_SRC)/.config"
	make -C "$(KERNEL_SRC)" ARCH="$(ARCH)" olddefconfig
	make -C "$(KERNEL_SRC)" ARCH="$(ARCH)" -j$$(nproc)

clean:
	rm -f hardened.config scpa_*.log

help:
	@echo "Targets:"
	@echo "  prune    Run SCPA to generate hardened.config (default)"
	@echo "  dry-run  Show what would be changed without writing"
	@echo "  compile  Compile kernel using generated config"
	@echo "  clean    Remove generated files"
	@echo ""
	@echo "Variables:"
	@echo "  KERNEL_SRC=$(KERNEL_SRC)"
	@echo "  ARCH=$(ARCH)"
	@echo "  PROFILE=$(PROFILE)  [embedded|server|desktop|iot]"
	@echo "  OUTPUT=$(OUTPUT)"
