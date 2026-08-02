# Makefile

CC = aarch64-openwrt-linux-gcc
CFLAGS = -Wall -Wextra -std=c11 -g -D_GNU_SOURCE
TARGET = devmem2
SOURCES = devmem2.c

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) $^ -o $@ -lm

install:
	cp $(TARGET) ../../rootfs/sbin/

clean:
	rm -f $(TARGET)

