#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Basic paths
# ============================================================

root_dir="$(git rev-parse --show-toplevel)"

build_dir="${BUILD_DIR:-$root_dir/.build}"
sdk_dir="$build_dir/sdk"
package_dir="$build_dir/packages"

openwrt_version="${OPENWRT_VERSION:-24.10.8}"

# ============================================================
# OpenWrt SDK
# ============================================================

sdk_url="${OPENWRT_SDK_URL:-https://downloads.openwrt.org/releases/${openwrt_version}/targets/armsr/armv8/openwrt-sdk-${openwrt_version}-armsr-armv8_gcc-13.3.0_musl.Linux-x86_64.tar.zst}"

sdk_sha256="${OPENWRT_SDK_SHA256:-5f430f5b30c9ea6dc472710356c139abf916b7ebd5de14e108e9cc204f40a2a4}"

# ============================================================
# External repositories
# ============================================================

ddns_go_repo="${DDNS_GO_REPO:-https://github.com/sirpdboy/luci-app-ddns-go.git}"

# Current ddns-go requires Go >= 1.25.
#
# Can be overridden with:
#
# DDNS_GO_REF=v6.17.1
#
ddns_go_ref="${DDNS_GO_REF:-v6.17.1}"

argon_repo="${ARGON_REPO:-https://github.com/jerrykuku/luci-theme-argon.git}"

argon_ref="${ARGON_REF:-master}"

# ============================================================
# Go toolchain
# ============================================================

GO_VERSION="${GO_VERSION:-1.25.3}"

GO_ARCHIVE="go${GO_VERSION}.linux-amd64.tar.gz"

GO_URL="https://go.dev/dl/${GO_ARCHIVE}"

GO_DIR="$build_dir/go-${GO_VERSION}"

GO_BIN="$GO_DIR/bin/go"

# ============================================================
# Prepare directories
# ============================================================

mkdir -p "$build_dir"
mkdir -p "$package_dir"

echo
echo "========================================"
echo "Build configuration"
echo "========================================"

echo "OpenWrt version : $openwrt_version"
echo "SDK directory   : $sdk_dir"
echo "Package dir     : $package_dir"
echo "ddns-go ref     : $ddns_go_ref"
echo "Argon ref       : $argon_ref"
echo "Go version      : $GO_VERSION"

echo "========================================"

# ============================================================
# Check host dependencies
# ============================================================

for command in \
	git \
	curl \
	tar \
	sha256sum \
	sed \
	find \
	unzip
do
	if ! command -v "$command" >/dev/null 2>&1; then
		echo "ERROR: required command '$command' is not installed"
		exit 1
	fi
done

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
# Download Go 1.25
# ============================================================

echo
echo "========================================"
echo "Preparing Go ${GO_VERSION}"
echo "========================================"

if [ ! -x "$GO_BIN" ]; then

	go_archive="$build_dir/$GO_ARCHIVE"

	echo "Go archive:"
	echo "$go_archive"

	if [ ! -f "$go_archive" ]; then

		echo
		echo "Downloading:"
		echo "$GO_URL"

		curl \
			--fail \
			--location \
			--retry 4 \
			--retry-delay 2 \
			"$GO_URL" \
			-o "$go_archive"

	fi

	echo
	echo "Extracting Go..."

	rm -rf "$GO_DIR"

	mkdir -p "$GO_DIR"

	tar \
		-xzf "$go_archive" \
		-C "$GO_DIR" \
		--strip-components=1

	echo "Go ${GO_VERSION} installed."

else

	echo "Go ${GO_VERSION} already exists."

fi

echo
echo "Go version:"
"$GO_BIN" version

# ============================================================
# Make Go 1.25 available first in PATH
# ============================================================

export PATH="$GO_DIR/bin:$PATH"

export GOROOT="$GO_DIR"

export GOTOOLCHAIN=local

echo
echo "========================================"
echo "Active Go toolchain"
echo "========================================"

which go

go version

echo "GOROOT=$GOROOT"

# ============================================================
# Clone ddns-go
# ============================================================

echo
echo "========================================"
echo "Cloning ddns-go source"
echo "========================================"

rm -rf "$build_dir/ddns-go-source"

echo "Repository : $ddns_go_repo"
echo "Reference  : $ddns_go_ref"

git clone \
	--depth 1 \
	--branch "$ddns_go_ref" \
	"$ddns_go_repo" \
	"$build_dir/ddns-go-source"

echo
echo "ddns-go commit:"

git -C "$build_dir/ddns-go-source" log -1 --oneline

# ============================================================
# Check ddns-go go.mod
# ============================================================

ddns_go_mod="$build_dir/ddns-go-source/ddns-go/go.mod"

if [ ! -f "$ddns_go_mod" ]; then
	echo "ERROR: ddns-go go.mod not found:"
	echo "$ddns_go_mod"
	exit 1
fi

echo
echo "========================================"
echo "ddns-go Go requirements"
echo "========================================"

grep -E '^(module|go|toolchain) ' \
	"$ddns_go_mod" \
	|| true

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

echo
echo "Argon commit:"

git -C "$build_dir/argon-source" log -1 --oneline

# ============================================================
# Modify Argon branding
# ============================================================

echo
echo "========================================"
echo "Applying Argon branding"
echo "========================================"

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
# Important:
#
# OpenWrt's Go package infrastructure normally uses:
#
#   staging_dir/host/bin/go
#
# and sets:
#
#   GOTOOLCHAIN=local
#
# Therefore replace the SDK host Go binary with Go 1.25.
#
# Keep a backup so the operation is reversible.
# ============================================================

echo
echo "========================================"
echo "Installing Go 1.25 into OpenWrt SDK"
echo "========================================"

sdk_go_dir="$sdk_dir/staging_dir/host/bin"
sdk_go="$sdk_go_dir/go"

mkdir -p "$sdk_go_dir"

if [ -e "$sdk_go" ] && [ ! -L "$sdk_go" ]; then

	echo "Backing up SDK Go binary..."

	mv \
		"$sdk_go" \
		"$sdk_go.openwrt"

fi

ln -sf \
	"$GO_BIN" \
	"$sdk_go"

echo
echo "OpenWrt SDK Go now points to:"
readlink -f "$sdk_go"

echo
echo "SDK Go version:"

"$sdk_go" version

# ============================================================
# Also expose Go through hostpkg if present
# ============================================================

hostpkg_go_dir="$sdk_dir/staging_dir/hostpkg/bin"
hostpkg_go="$hostpkg_go_dir/go"

if [ -d "$hostpkg_go_dir" ]; then

	if [ -e "$hostpkg_go" ] && [ ! -L "$hostpkg_go" ]; then
		mv \
			"$hostpkg_go" \
			"$hostpkg_go.openwrt"
	fi

	ln -sf \
		"$GO_BIN" \
		"$hostpkg_go"

	echo
	echo "hostpkg Go:"
	"$hostpkg_go" version || true

fi

# ============================================================
# Verify SDK target architecture
# ============================================================

echo
echo "========================================"
echo "OpenWrt target configuration"
echo "========================================"

pushd "$sdk_dir" >/dev/null

./scripts/feeds update -a

./scripts/feeds install -a

make defconfig

echo
echo "Target:"
grep '^CONFIG_TARGET_ARCH_PACKAGES=' .config || true

echo
echo "Target architecture:"
grep '^CONFIG_ARCH=' .config || true

echo
echo "========================================"
echo "Go toolchain used by SDK"
echo "========================================"

"$sdk_dir/staging_dir/host/bin/go" version

echo
echo "========================================"
echo "Compiling external packages"
echo "========================================"

# Force the environment used by the OpenWrt build
# to see Go 1.25 first.

export PATH="$GO_DIR/bin:$sdk_dir/staging_dir/host/bin:$PATH"
export GOROOT="$GO_DIR"
export GOTOOLCHAIN=local

echo
echo "PATH:"
echo "$PATH"

echo
echo "go:"
which go

go version

echo
echo "SDK go:"
"$sdk_dir/staging_dir/host/bin/go" version

echo
echo "Building ddns-go..."

make \
	package/ddns-go/compile \
	V=s

echo
echo "Building luci-app-ddns-go..."

make \
	package/luci-app-ddns-go/compile \
	V=s

echo
echo "Building luci-theme-argon..."

make \
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

ddns_ipk="$(
	find "$package_dir" \
		-maxdepth 1 \
		-type f \
		-name 'ddns-go_*.ipk' \
		-print -quit
)"

app_ipk="$(
	find "$package_dir" \
		-maxdepth 1 \
		-type f \
		-name 'luci-app-ddns-go_*.ipk' \
		-print -quit
)"

argon_ipk="$(
	find "$package_dir" \
		-maxdepth 1 \
		-type f \
		-name 'luci-theme-argon_*.ipk' \
		-print -quit
)"

if [ -z "$ddns_ipk" ]; then
	echo "ERROR: ddns-go IPK was not generated."
	exit 1
fi

if [ -z "$app_ipk" ]; then
	echo "ERROR: luci-app-ddns-go IPK was not generated."
	exit 1
fi

if [ -z "$argon_ipk" ]; then
	echo "ERROR: luci-theme-argon IPK was not generated."
	exit 1
fi

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
