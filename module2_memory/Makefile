obj-m += mmoa.o

KDIR  ?= /lib/modules/$(shell uname -r)/build
PWD   := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

load:
	insmod mmoa.ko

unload:
	rmmod mmoa || true

reload: unload load

status:
	@lsmod | grep mmoa || echo "mmoa not loaded"
	@cat /proc/mmoa_stats 2>/dev/null || echo "/proc/mmoa_stats not present"

tune:
	bash mmoa_tune.sh embedded

.PHONY: all clean load unload reload status tune
