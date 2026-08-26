#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Paths
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

ddns_go_ref="${DDNS_GO_REF:-v6.17.1}"

argon_repo="${ARGON_REPO:-https://github.com/jerrykuku/luci-theme-argon.git}"

argon_ref="${ARGON_REF:-master}"

# ============================================================
# Go
# ============================================================

GO_VERSION="${GO_VERSION:-1.25.3}"

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
echo "SDK             : $sdk_dir"
echo "ddns-go         : $ddns_go_ref"
echo "Argon           : $argon_ref"
echo "Go              : $GO_VERSION"

# ============================================================
# Dependencies
# ============================================================

for command in \
    git \
    curl \
    tar \
    sha256sum \
    sed \
    find \
    python3
do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "ERROR: required command '$command' is not installed"
        exit 1
    fi
done

# ============================================================
# Download SDK
# ============================================================

if [ ! -d "$sdk_dir" ]; then

    archive="$build_dir/openwrt-sdk.tar.zst"

    echo
    echo "========================================"
    echo "Downloading OpenWrt SDK"
    echo "========================================"

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

    echo "$sdk_sha256  $archive" \
        | sha256sum --check --status

    mkdir -p "$sdk_dir"

    tar \
        --zstd \
        -xf "$archive" \
        --strip-components=1 \
        -C "$sdk_dir"

else

    echo
    echo "Using existing SDK:"
    echo "$sdk_dir"

fi

# ============================================================
# Update feeds FIRST
# ============================================================

echo
echo "========================================"
echo "Updating OpenWrt feeds"
echo "========================================"

pushd "$sdk_dir" >/dev/null

./scripts/feeds update -a

./scripts/feeds install -a

popd >/dev/null

# ============================================================
# Patch Go
# ============================================================

echo
echo "========================================"
echo "Updating OpenWrt Go toolchain"
echo "========================================"

export GO_VERSION

chmod +x \
    "$root_dir/scripts/patch_golang_125.sh"

"$root_dir/scripts/patch_golang_125.sh"

# ============================================================
# Verify Go
# ============================================================

echo
echo "========================================"
echo "Go verification"
echo "========================================"

SDK_GO="$sdk_dir/staging_dir/host/bin/go"

if [ ! -x "$SDK_GO" ]; then
    echo "ERROR: SDK Go not found:"
    echo "$SDK_GO"
    exit 1
fi

"$SDK_GO" version

# ============================================================
# Clone ddns-go
# ============================================================

echo
echo "========================================"
echo "Cloning ddns-go"
echo "========================================"

rm -rf "$build_dir/ddns-go-source"

git clone \
    --depth 1 \
    --branch "$ddns_go_ref" \
    "$ddns_go_repo" \
    "$build_dir/ddns-go-source"

echo
echo "ddns-go commit:"

git \
    -C "$build_dir/ddns-go-source" \
    log -1 --oneline

# ============================================================
# Show Go requirement
# ============================================================

ddns_go_mod="$build_dir/ddns-go-source/ddns-go/go.mod"

if [ ! -f "$ddns_go_mod" ]; then

    echo "ERROR: ddns-go go.mod not found:"
    echo "$ddns_go_mod"

    exit 1
fi

echo
echo "========================================"
echo "ddns-go Go requirement"
echo "========================================"

grep -E \
    '^(module|go|toolchain) ' \
    "$ddns_go_mod" \
    || true

# ============================================================
# Clone Argon
# ============================================================

echo
echo "========================================"
echo "Cloning Argon"
echo "========================================"

rm -rf "$build_dir/argon-source"

git clone \
    --depth 1 \
    --branch "$argon_ref" \
    "$argon_repo" \
    "$build_dir/argon-source"

echo
echo "Argon commit:"

git \
    -C "$build_dir/argon-source" \
    log -1 --oneline

# ============================================================
# Argon branding
# ============================================================

echo
echo "========================================"
echo "Applying Argon branding"
echo "========================================"

sed -i \
    's/{{ hostname }}/5Breeze/g' \
    "$build_dir/argon-source/ucode/template/themes/argon/head_meta.ut" \
    "$build_dir/argon-source/ucode/template/themes/argon/header.ut" \
    "$build_dir/argon-source/ucode/template/themes/argon/sysauth.ut"

# ============================================================
# Install packages
# ============================================================

echo
echo "========================================"
echo "Installing packages into SDK"
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

# ============================================================
# Defconfig
# ============================================================

echo
echo "========================================"
echo "OpenWrt defconfig"
echo "========================================"

pushd "$sdk_dir" >/dev/null

make defconfig

# ============================================================
# Final Go check immediately before build
# ============================================================

echo
echo "========================================"
echo "Go immediately before package build"
echo "========================================"

echo "SDK Go:"
"$sdk_dir/staging_dir/host/bin/go" version

echo
echo "Go path:"
readlink -f "$sdk_dir/staging_dir/host/bin/go" || true

echo
echo "Environment:"
echo "GOTOOLCHAIN=${GOTOOLCHAIN:-<unset>}"

# The SDK Go is deliberately used as the first Go executable.

export PATH="$sdk_dir/staging_dir/host/bin:$PATH"

export GOTOOLCHAIN=local

echo
echo "Active Go:"
which go

go version

# ============================================================
# Build
# ============================================================

echo
echo "========================================"
echo "Building ddns-go"
echo "========================================"

make \
    package/ddns-go/compile \
    V=s

echo
echo "========================================"
echo "Building luci-app-ddns-go"
echo "========================================"

make \
    package/luci-app-ddns-go/compile \
    V=s

echo
echo "========================================"
echo "Building luci-theme-argon"
echo "========================================"

make \
    package/luci-theme-argon/compile \
    V=s

popd >/dev/null

# ============================================================
# Collect IPKs
# ============================================================

echo
echo "========================================"
echo "Collecting IPK packages"
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
# Verify
# ============================================================

echo
echo "========================================"
echo "Verifying packages"
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
    echo "ERROR: ddns-go IPK not found."
    exit 1
fi

if [ -z "$app_ipk" ]; then
    echo "ERROR: luci-app-ddns-go IPK not found."
    exit 1
fi

if [ -z "$argon_ipk" ]; then
    echo "ERROR: luci-theme-argon IPK not found."
    exit 1
fi

# ============================================================
# Output
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
echo "BUILD SUCCESS"
echo "========================================"
