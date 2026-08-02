# Makefile

CC = aarch64-openwrt-linux-gcc
CFLAGS = -Wall -Wextra -std=c11 -g -D_GNU_SOURCE
TARGET = eth_setup
SOURCES = main.c

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) $^ -o $@ -lm

install:
	cp $(TARGET) ../../rootfs/sbin/

clean:
	rm -f $(TARGET)

