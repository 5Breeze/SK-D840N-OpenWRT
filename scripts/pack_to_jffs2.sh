#!/bin/bash

# sudo apt install mtd-utils
mkfs.jffs2 -d rootfs -l -n -s 0x800 -e 0x20000 -o rootfs.jffs2

