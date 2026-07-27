#!/bin/bash

cd rootfs
find . -print0 | sort -z | cpio -H newc -o --null > ../ramdisk.cpio
cd -

# gzip
# find . | cpio -o -H newc | gzip > ../ramdisk.cpio.gz
gzip -9 -c ramdisk.cpio > ramdisk.cpio.gz

#lzma
lzma -k -9 -e -c ramdisk.cpio > ramdisk.cpio.lzma

