#!/bin/bash

# sudo apt install mtd-utils
root_dir=$(git rev-parse --show-toplevel)
rootfs_dir="${ROOTFS_DIR:-$root_dir/rootfs}"
output_file="${OUTPUT_FILE:-$root_dir/rootfs.jffs2}"
mkfs.jffs2 -d "$rootfs_dir" -l -n -s 0x800 -e 0x20000 -o "$output_file"

