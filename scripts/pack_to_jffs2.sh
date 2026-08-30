#!/bin/bash

# sudo apt install mtd-utils
# Git does not preserve Unix ownership and GitHub checks files out as the
# runner user. Always encode root:root ownership in the firmware image.
mkfs.jffs2 -d rootfs -l -n --squash-uids -s 0x800 -e 0x20000 -o rootfs.jffs2

