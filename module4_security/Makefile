obj-m += acm_lsm.o

KDIR  ?= /lib/modules/$(shell uname -r)/build
PWD   := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

load:
	insmod acm_lsm.ko

unload:
	rmmod acm_lsm || true

reload: unload load

status:
	@lsmod | grep acm_lsm || echo "acm_lsm not loaded"
	@cat /proc/acm_policy 2>/dev/null || echo "/proc/acm_policy not present"

# Load a sample policy: trusted label gets all access, default gets read/write/exec
demo_policy:
	@echo "Registering labels …"
	echo "LABEL trusted"   > /proc/acm_policy
	echo "LABEL default"   > /proc/acm_policy
	echo "LABEL kernel"    > /proc/acm_policy
	@echo "Allowing trusted -> any : all"
	echo "ALLOW trusted any all"  > /proc/acm_policy
	@echo "Allowing default -> default : read,write,exec,mmap_exec"
	echo "ALLOW default default read,write,exec,mmap_exec" > /proc/acm_policy
	@echo "Allowing default -> kernel : net"
	echo "ALLOW default kernel net"  > /proc/acm_policy
	cat /proc/acm_policy

.PHONY: all clean load unload reload status demo_policy
