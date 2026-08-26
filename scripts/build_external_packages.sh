#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(git rev-parse --show-toplevel)
build_dir="${BUILD_DIR:-$root_dir/.build}"
sdk_dir="$build_dir/sdk"
package_dir="$build_dir/packages"
openwrt_version="${OPENWRT_VERSION:-24.10.8}"
sdk_url="${OPENWRT_SDK_URL:-https://downloads.openwrt.org/releases/${openwrt_version}/targets/armsr/armv8/openwrt-sdk-${openwrt_version}-armsr-armv8_gcc-13.3.0_musl.Linux-x86_64.tar.zst}"
sdk_sha256="${OPENWRT_SDK_SHA256:-5f430f5b30c9ea6dc472710356c139abf916b7ebd5de14e108e9cc204f40a2a4}"
ddns_go_repo="${DDNS_GO_REPO:-https://github.com/sirpdboy/luci-app-ddns-go.git}"
ddns_go_ref="${DDNS_GO_REF:-main}"
argon_repo="${ARGON_REPO:-https://github.com/jerrykuku/luci-theme-argon.git}"
argon_ref="${ARGON_REF:-main}"

mkdir -p "$build_dir" "$package_dir"

if [ ! -d "$sdk_dir" ]; then
	archive="$build_dir/openwrt-sdk.tar.zst"
	if [ ! -f "$archive" ]; then
		curl --fail --location --retry 4 --retry-delay 2 "$sdk_url" -o "$archive"
	fi
	echo "$sdk_sha256  $archive" | sha256sum --check --status
	mkdir -p "$sdk_dir"
	tar --zstd -xf "$archive" --strip-components=1 -C "$sdk_dir"
fi

rm -rf "$build_dir/ddns-go-source"
git clone --depth 1 --branch "$ddns_go_ref" "$ddns_go_repo" "$build_dir/ddns-go-source"
rm -rf "$build_dir/argon-source"
git clone --depth 1 --branch "$argon_ref" "$argon_repo" "$build_dir/argon-source"

# Argon renders the hostname in the top bar and login page. Make the product
# name independent from the runtime hostname and keep it consistent everywhere.
sed -i 's/{{ hostname }}/5Breeze/g' \
	"$build_dir/argon-source/ucode/template/themes/argon/head_meta.ut" \
	"$build_dir/argon-source/ucode/template/themes/argon/header.ut" \
	"$build_dir/argon-source/ucode/template/themes/argon/sysauth.ut"

rm -rf "$sdk_dir/package/ddns-go" "$sdk_dir/package/luci-app-ddns-go" "$sdk_dir/package/luci-theme-argon"
cp -a "$build_dir/ddns-go-source/ddns-go" "$sdk_dir/package/ddns-go"
cp -a "$build_dir/ddns-go-source/luci-app-ddns-go" "$sdk_dir/package/luci-app-ddns-go"
cp -a "$build_dir/argon-source" "$sdk_dir/package/luci-theme-argon"

pushd "$sdk_dir" >/dev/null
./scripts/feeds update -a
./scripts/feeds install -a
make defconfig
make package/ddns-go/compile package/luci-app-ddns-go/compile package/luci-theme-argon/compile V=s
popd >/dev/null

find "$sdk_dir/bin/packages" -type f \( \
	-name 'ddns-go_*.ipk' -o \
	-name 'luci-app-ddns-go_*.ipk' -o \
	-name 'luci-theme-argon_*.ipk' \
\) -exec cp -f {} "$package_dir/" \;

test -n "$(find "$package_dir" -maxdepth 1 -type f -name 'ddns-go_*.ipk' -print -quit)"
test -n "$(find "$package_dir" -maxdepth 1 -type f -name 'luci-app-ddns-go_*.ipk' -print -quit)"
test -n "$(find "$package_dir" -maxdepth 1 -type f -name 'luci-theme-argon_*.ipk' -print -quit)"

echo "Built external packages:"
find "$package_dir" -maxdepth 1 -type f -printf '%f\n' | sort
