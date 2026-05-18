obj-m += rbpf.o

KDIR  ?= /lib/modules/$(shell uname -r)/build
PWD   := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

load:
	insmod rbpf.ko

unload:
	rmmod rbpf || true

reload: unload load

status:
	@lsmod | grep rbpf || echo "rbpf not loaded"
	@cat /proc/rbpf_rules 2>/dev/null || echo "/proc/rbpf_rules not present"

# Example: whitelist SSH (port 22) and HTTP (port 80) from any source
demo_rules:
	@echo "Flushing existing rules …"
	echo "FLUSH" > /proc/rbpf_rules
	@echo "Allow loopback (already installed by module default)"
	@echo "Allow SSH in from any"
	echo "ADD 10 0.0.0.0/0 0.0.0.0/0 0-0 22-22 tcp accept" > /proc/rbpf_rules
	@echo "Allow HTTP in from any"
	echo "ADD 20 0.0.0.0/0 0.0.0.0/0 0-0 80-80 tcp accept" > /proc/rbpf_rules
	@echo "Allow HTTPS in from any"
	echo "ADD 30 0.0.0.0/0 0.0.0.0/0 0-0 443-443 tcp accept" > /proc/rbpf_rules
	@echo "Allow DNS out"
	echo "ADD 40 0.0.0.0/0 0.0.0.0/0 0-0 53-53 udp accept" > /proc/rbpf_rules
	@echo "Log everything else (default DROP)"
	cat /proc/rbpf_rules

.PHONY: all clean load unload reload status demo_rules
