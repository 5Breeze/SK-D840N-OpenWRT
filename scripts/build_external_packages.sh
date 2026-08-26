#!/usr/bin/env bash

set -Eeuo pipefail

root_dir="$(git rev-parse --show-toplevel)"
build_dir="${BUILD_DIR:-$root_dir/.build}"
sdk_dir="$build_dir/sdk"
package_dir="$build_dir/packages"

openwrt_version="${OPENWRT_VERSION:-24.10.8}"

sdk_url="${OPENWRT_SDK_URL:-https://downloads.openwrt.org/releases/${openwrt_version}/targets/armsr/armv8/openwrt-sdk-${openwrt_version}-armsr-armv8_gcc-13.3.0_musl.Linux-x86_64.tar.zst}"

sdk_sha256="${OPENWRT_SDK_SHA256:-5f430f5b30c9ea6dc472710356c139abf916b7ebd5de14e108e9cc204f40a2a4}"

# ============================================================
# External repositories
# ============================================================

ddns_go_repo="${DDNS_GO_REPO:-https://github.com/sirpdboy/luci-app-ddns-go.git}"

# Do NOT force main here.
# Empty value means use the repository default branch.
ddns_go_ref="${DDNS_GO_REF:-}"

argon_repo="${ARGON_REPO:-https://github.com/jerrykuku/luci-theme-argon.git}"

# Argon currently uses master.
argon_ref="${ARGON_REF:-master}"

# ============================================================
# Prepare directories
# ============================================================

mkdir -p "$build_dir"
mkdir -p "$package_dir"

echo "========================================"
echo "OpenWrt version : $openwrt_version"
echo "Build directory : $build_dir"
echo "SDK directory   : $sdk_dir"
echo "Package dir     : $package_dir"
echo "========================================"

# ============================================================
# Check dependencies
# ============================================================

command -v git >/dev/null 2>&1 || {
	echo "ERROR: git is not installed"
	exit 1
}

command -v curl >/dev/null 2>&1 || {
	echo "ERROR: curl is not installed"
	exit 1
}

command -v tar >/dev/null 2>&1 || {
	echo "ERROR: tar is not installed"
	exit 1
}

command -v sha256sum >/dev/null 2>&1 || {
	echo "ERROR: sha256sum is not installed"
	exit 1
}

# ============================================================
# Download OpenWrt SDK
# ============================================================

if [ ! -d "$sdk_dir" ]; then

	archive="$build_dir/openwrt-sdk.tar.zst"

	echo
	echo "========================================"
	echo "Downloading OpenWrt SDK"
	echo "========================================"
	echo "URL:"
	echo "$sdk_url"

	if [ ! -f "$archive" ]; then
		curl \
			--fail \
			--location \
			--retry 4 \
			--retry-delay 2 \
			"$sdk_url" \
			-o "$archive"
	fi

	echo
	echo "Checking SDK SHA256..."

	echo "$sdk_sha256  $archive" | sha256sum --check --status

	echo "SDK SHA256 OK"

	mkdir -p "$sdk_dir"

	echo
	echo "Extracting SDK..."

	tar \
		--zstd \
		-xf "$archive" \
		--strip-components=1 \
		-C "$sdk_dir"

	echo "SDK extracted."

else

	echo
	echo "OpenWrt SDK already exists:"
	echo "$sdk_dir"

fi

# ============================================================
# Clone ddns-go
# ============================================================

echo
echo "========================================"
echo "Cloning ddns-go source"
echo "========================================"

rm -rf "$build_dir/ddns-go-source"

if [ -n "$ddns_go_ref" ]; then

	echo "Repository : $ddns_go_repo"
	echo "Reference  : $ddns_go_ref"

	git clone \
		--depth 1 \
		--branch "$ddns_go_ref" \
		"$ddns_go_repo" \
		"$build_dir/ddns-go-source"

else

	echo "Repository : $ddns_go_repo"
	echo "Reference  : repository default branch"

	git clone \
		--depth 1 \
		"$ddns_go_repo" \
		"$build_dir/ddns-go-source"

fi

# ============================================================
# Clone Argon
# ============================================================

echo
echo "========================================"
echo "Cloning Argon source"
echo "========================================"

rm -rf "$build_dir/argon-source"

echo "Repository : $argon_repo"
echo "Reference  : $argon_ref"

git clone \
	--depth 1 \
	--branch "$argon_ref" \
	"$argon_repo" \
	"$build_dir/argon-source"

# ============================================================
# Show cloned versions
# ============================================================

echo
echo "========================================"
echo "Source versions"
echo "========================================"

echo "ddns-go:"
git -C "$build_dir/ddns-go-source" log -1 --oneline

echo

echo "Argon:"
git -C "$build_dir/argon-source" log -1 --oneline

# ============================================================
# Modify Argon branding
# ============================================================

echo
echo "========================================"
echo "Applying Argon branding"
echo "========================================"

# Argon renders the hostname in the top bar
# and login page.
#
# Replace the runtime hostname with 5Breeze.

sed -i 's/{{ hostname }}/5Breeze/g' \
	"$build_dir/argon-source/ucode/template/themes/argon/head_meta.ut" \
	"$build_dir/argon-source/ucode/template/themes/argon/header.ut" \
	"$build_dir/argon-source/ucode/template/themes/argon/sysauth.ut"

echo "Argon branding applied."

# ============================================================
# Install packages into SDK
# ============================================================

echo
echo "========================================"
echo "Installing external packages into SDK"
echo "========================================"

rm -rf \
	"$sdk_dir/package/ddns-go" \
	"$sdk_dir/package/luci-app-ddns-go" \
	"$sdk_dir/package/luci-theme-argon"

cp -a \
	"$build_dir/ddns-go-source/ddns-go" \
	"$sdk_dir/package/ddns-go"

cp -a \
	"$build_dir/ddns-go-source/luci-app-ddns-go" \
	"$sdk_dir/package/luci-app-ddns-go"

cp -a \
	"$build_dir/argon-source" \
	"$sdk_dir/package/luci-theme-argon"

echo "External packages installed."

# ============================================================
# Build packages
# ============================================================

echo
echo "========================================"
echo "Updating OpenWrt feeds"
echo "========================================"

pushd "$sdk_dir" >/dev/null

./scripts/feeds update -a

./scripts/feeds install -a

echo
echo "========================================"
echo "Running OpenWrt defconfig"
echo "========================================"

make defconfig

echo
echo "========================================"
echo "Compiling external packages"
echo "========================================"

make \
	package/ddns-go/compile \
	package/luci-app-ddns-go/compile \
	package/luci-theme-argon/compile \
	V=s

popd >/dev/null

# ============================================================
# Collect packages
# ============================================================

echo
echo "========================================"
echo "Collecting generated IPK packages"
echo "========================================"

find "$sdk_dir/bin/packages" \
	-type f \
	\( \
		-name 'ddns-go_*.ipk' \
		-o -name 'luci-app-ddns-go_*.ipk' \
		-o -name 'luci-theme-argon_*.ipk' \
	\) \
	-exec cp -f {} "$package_dir/" \;

# ============================================================
# Verify packages
# ============================================================

echo
echo "========================================"
echo "Verifying generated packages"
echo "========================================"

test -n "$(
	find "$package_dir" \
		-maxdepth 1 \
		-type f \
		-name 'ddns-go_*.ipk' \
		-print -quit
)"

test -n "$(
	find "$package_dir" \
		-maxdepth 1 \
		-type f \
		-name 'luci-app-ddns-go_*.ipk' \
		-print -quit
)"

test -n "$(
	find "$package_dir" \
		-maxdepth 1 \
		-type f \
		-name 'luci-theme-argon_*.ipk' \
		-print -quit
)"

# ============================================================
# Final output
# ============================================================

echo
echo "========================================"
echo "Built external packages"
echo "========================================"

find "$package_dir" \
	-maxdepth 1 \
	-type f \
	-printf '%f\n' \
	| sort

echo
echo "========================================"
echo "External package build completed"
echo "========================================"
