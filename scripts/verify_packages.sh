#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(git rev-parse --show-toplevel)
rootfs_dir="${ROOTFS_DIR:-$root_dir/rootfs}"
status_file="$rootfs_dir/usr/lib/opkg/status"

for package in \
	luci-theme-argon \
	luci-i18n-base-zh-cn \
	luci-i18n-firewall-zh-cn \
	luci-i18n-package-manager-zh-cn \
	luci-i18n-upnp-zh-cn \
	luci-app-upnp \
	miniupnpd-nftables \
	v2ray-core \
	v2ray-geoip \
	v2ray-geosite \
	tailscale \
	ddns-go \
	luci-app-ddns-go \
	kmod-tun; do
	if ! awk -v package="$package" '
		$0 == "Package: " package { found = 1 }
		END { exit(found ? 0 : 1) }
	' "$status_file"; then
		echo "Missing installed package: $package" >&2
		exit 1
	fi
done

echo "Verified OpenWrt package set:"
awk '/^Package: (luci-theme-argon|luci-i18n-base-zh-cn|luci-i18n-firewall-zh-cn|luci-i18n-package-manager-zh-cn|luci-i18n-upnp-zh-cn|luci-app-upnp|miniupnpd-nftables|v2ray-core|v2ray-geoip|v2ray-geosite|tailscale|ddns-go|luci-app-ddns-go|kmod-tun)$/{show=1} show{print} show && /^$/{show=0}' "$status_file"
