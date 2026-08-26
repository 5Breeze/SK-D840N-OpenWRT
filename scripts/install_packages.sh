#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(git rev-parse --show-toplevel)
rootfs_dir="${ROOTFS_DIR:-$root_dir/rootfs}"
build_dir="${BUILD_DIR:-$root_dir/.build}"
package_dir="$build_dir/packages"
openwrt_version="${OPENWRT_VERSION:-24.10.8}"
feed_mirror="${OPENWRT_MIRROR:-https://downloads.openwrt.org}"
feed_mirror="${feed_mirror%/}"

test -x "$rootfs_dir/bin/opkg"
test -d "$package_dir"

mapfile -t packages < <(sed -e 's/[[:space:]]*#.*//' -e '/^[[:space:]]*$/d' "$root_dir/config/packages.txt")
if [ -n "${EXTRA_PACKAGES:-}" ]; then
	read -r -a extra_packages <<< "$EXTRA_PACKAGES"
	packages+=("${extra_packages[@]}")
fi

# The checked-in feed file is kept for router-side package management. During
# CI, force the package feed to the same OpenWrt release as the checked-in
# rootfs. The mirror can be overridden for a restricted network.
sed -i -E "s#https?://[^/]+(/openwrt)?/(releases|snapshots)/#${feed_mirror}/\2/#g" \
	"$rootfs_dir/etc/opkg/distfeeds.conf"
sed -i -E "s#(https?://[^/]+/)(releases|snapshots)/[^/]+#\1\2/${openwrt_version}#g" \
	"$rootfs_dir/etc/opkg/distfeeds.conf"

qemu_bin="$(command -v qemu-aarch64-static || true)"
if [ -z "$qemu_bin" ]; then
	echo "qemu-aarch64-static is required to run the target opkg in CI" >&2
	exit 1
fi

sudo install -D -m 0755 "$qemu_bin" "$rootfs_dir/usr/bin/qemu-aarch64-static"

tmp_dir="$rootfs_dir/tmp/sk-d840n-packages"
resolver_file="$rootfs_dir/tmp/resolv.conf"
sudo mkdir -p "$tmp_dir"
sudo cp -f "$package_dir"/*.ipk "$tmp_dir/"
sudo cp -f /etc/resolv.conf "$resolver_file"

cleanup() {
	if [ "${mounted_proc:-0}" -eq 1 ]; then
		sudo umount "$rootfs_dir/proc" || true
	fi
	if [ -d "$tmp_dir" ]; then
		sudo rm -rf "$tmp_dir"
	fi
	sudo rm -f "$resolver_file"
	sudo rm -f "$rootfs_dir/usr/bin/qemu-aarch64-static"
}
trap cleanup EXIT

sudo mount --bind /proc "$rootfs_dir/proc"
mounted_proc=1

sudo chroot "$rootfs_dir" /usr/bin/qemu-aarch64-static /bin/sh -c \
	"opkg update && opkg install $tmp_dir/*.ipk ${packages[*]}"

sudo rm -f "$rootfs_dir/usr/bin/qemu-aarch64-static"
sudo rm -rf "$tmp_dir"
mounted_proc=0
sudo umount "$rootfs_dir/proc"
