#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-${repo_dir}/rootfs.jffs2}"
mkfs_jffs2="$(command -v mkfs.jffs2)"
test -n "${mkfs_jffs2}"

# Git does not preserve Unix ownership and GitHub checks files out as the
# runner user. opkg, however, runs inside the chroot as root and can create
# files that the runner cannot read. Build the image as root, encode root:root
# ownership in the firmware, then return the artifact to the runner.
sudo "${mkfs_jffs2}" \
    -d "${repo_dir}/rootfs" \
    -l -n --squash-uids -s 0x800 -e 0x20000 \
    -o "${output}"
sudo chown "$(id -u):$(id -g)" "${output}"
test -s "${output}"

