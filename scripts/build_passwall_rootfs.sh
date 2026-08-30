#!/usr/bin/env bash
set -euo pipefail

# Build PassWall for the exact OpenWrt userspace/kernel ABI used by SK-D840N,
# then install the resulting IPKs into the repository rootfs.

OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.8}"
SDK_FILE="openwrt-sdk-${OPENWRT_VERSION}-armsr-armv8_gcc-13.3.0_musl.Linux-x86_64.tar.zst"
SDK_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/armsr/armv8/${SDK_FILE}"
PASSWALL_REPO="${PASSWALL_REPO:-https://github.com/Openwrt-Passwall/openwrt-passwall.git}"
PASSWALL_PACKAGES_REPO="${PASSWALL_PACKAGES_REPO:-https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git}"
ARGON_REPO="${ARGON_REPO:-https://github.com/jerrykuku/luci-theme-argon.git}"
ARGON_CONFIG_REPO="${ARGON_CONFIG_REPO:-https://github.com/jerrykuku/luci-app-argon-config.git}"

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${BUILD_DIR:-${repo_dir}/.build-passwall}"
download_dir="${build_dir}/downloads"
sdk_dir="${build_dir}/sdk"
rootfs_dir="${repo_dir}/rootfs"

rm -rf "${build_dir}"
mkdir -p "${download_dir}" "${sdk_dir}"

run_quiet() {
    local label="$1"
    local logfile="$2"
    shift 2

    echo "::group::${label}"
    echo "[build] ${label}..."
    if "$@" >"${logfile}" 2>&1; then
        echo "[build] ${label}: done"
    else
        local status=$?
        echo "[build] ${label}: failed (last 250 log lines)" >&2
        tail -n 250 "${logfile}" >&2 || true
        echo "::endgroup::"
        return "${status}"
    fi
    echo "::endgroup::"
}

curl --fail --location --retry 5 --silent --show-error \
    --output "${download_dir}/${SDK_FILE}" "${SDK_URL}"
tar --zstd -xf "${download_dir}/${SDK_FILE}" -C "${sdk_dir}" --strip-components=1

git clone --quiet --depth 1 "${PASSWALL_REPO}" "${sdk_dir}/package/passwall-luci"
git clone --quiet --depth 1 "${PASSWALL_PACKAGES_REPO}" "${sdk_dir}/package/passwall-packages"
git clone --quiet --depth 1 "${ARGON_REPO}" "${sdk_dir}/package/luci-theme-argon"
git clone --quiet --depth 1 "${ARGON_CONFIG_REPO}" "${sdk_dir}/package/luci-app-argon-config"

cd "${sdk_dir}"
run_quiet "Update OpenWrt feeds" "${build_dir}/feeds-update.log" \
    ./scripts/feeds update -a
run_quiet "Install OpenWrt feeds" "${build_dir}/feeds-install.log" \
    ./scripts/feeds install -a

# Keep the image practical for 256 MiB NAND: nftables + Xray provides the
# modern PassWall path without also embedding every optional proxy core.
cat >> .config <<'EOF'
CONFIG_ALL_NONSHARED=n
CONFIG_ALL_KMODS=n
CONFIG_ALL=n
CONFIG_AUTOREMOVE=n
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_luci-app-passwall=m
# CONFIG_PACKAGE_luci-app-passwall_Iptables_Transparent_Proxy is not set
CONFIG_PACKAGE_luci-app-passwall_Nftables_Transparent_Proxy=y
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Geoview is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Haproxy is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Hysteria is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_NaiveProxy is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Server is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Server is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadow_TLS is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Simple_Obfs is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_V2ray_Geodata is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_V2ray_Plugin is not set
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray_Plugin is not set
CONFIG_PACKAGE_luci-theme-argon=m
CONFIG_PACKAGE_luci-app-argon-config=m
EOF

run_quiet "Resolve build configuration" "${build_dir}/defconfig.log" \
    make defconfig

# A package-specific compile target does not reliably build every selected
# runtime dependency in an SDK. Build the complete set selected by defconfig,
# otherwise packages such as ipt2socks can be absent from bin/packages even
# though luci-app-passwall itself compiled successfully.
run_quiet "Download package sources" "${build_dir}/download.log" \
    make -j8 download
run_quiet "Compile selected packages" "${build_dir}/compile.log" \
    make -j"$(nproc)" package/compile

ipk_dir="${rootfs_dir}/tmp/passwall-ipks"
mkdir -p "${ipk_dir}"

copy_ipk() {
    local package="$1"
    local required="${2:-yes}"
    local candidate
    candidate="$(find "${sdk_dir}/bin" -type f -name "${package}_*.ipk" -print -quit)"
    if [[ -z "${candidate}" ]]; then
        if [[ "${required}" == "yes" ]]; then
            echo "Required package was not produced: ${package}" >&2
            exit 1
        fi
        return 0
    fi
    cp "${candidate}" "${ipk_dir}/"
}

for package in \
    chinadns-ng dns2socks ipt2socks microsocks tcping xray-core \
    luci-app-passwall luci-theme-argon luci-app-argon-config; do
    copy_ipk "${package}"
done
copy_ipk luci-i18n-passwall-zh-cn no
copy_ipk luci-i18n-argon-config-zh-cn no

# qemu-user-static lets the CI host run the rootfs' native aarch64 opkg. Using
# --offline-root also prevents package post-install scripts from starting
# router services inside the build host.
qemu_bin="$(command -v qemu-aarch64-static)"
cp "${qemu_bin}" "${rootfs_dir}/usr/bin/qemu-aarch64-static"
cp /etc/resolv.conf "${rootfs_dir}/tmp/resolv.conf"

chroot_opkg() {
    sudo chroot "${rootfs_dir}" /usr/bin/qemu-aarch64-static \
        /bin/opkg --offline-root / "$@"
}

chroot_opkg update

# PassWall's nftables mode needs dnsmasq-full. It intentionally replaces the
# smaller dnsmasq package from the base rootfs.
chroot_opkg remove dnsmasq || true
chroot_opkg install \
    dnsmasq-full coreutils coreutils-base64 coreutils-nohup coreutils-timeout \
    curl ip-full libuci-lua lua luci-compat luci-lib-jsonc lyaml nftables \
    resolveip unzip kmod-nft-nat kmod-nft-socket kmod-nft-tproxy

mapfile -t local_ipks < <(
    find "${ipk_dir}" -maxdepth 1 -type f -name '*.ipk' \
        -printf '/tmp/passwall-ipks/%f\n' | sort
)
chroot_opkg install "${local_ipks[@]}"
chroot_opkg install \
    luci-i18n-base-zh-cn luci-i18n-package-manager-zh-cn \
    luci-i18n-firewall-zh-cn || true

rm -f "${rootfs_dir}/usr/bin/qemu-aarch64-static" "${rootfs_dir}/tmp/resolv.conf"
rm -rf "${ipk_dir}"

# Argon remains selectable in LuCI, and is the default on first boot.
sed -i 's#option mediaurlbase /luci-static/[^[:space:]]*#option mediaurlbase /luci-static/argon#' \
    "${rootfs_dir}/etc/config/luci"

test -x "${rootfs_dir}/bin/opkg"
test -f "${rootfs_dir}/usr/lib/opkg/info/luci-app-package-manager.control"
test -f "${rootfs_dir}/usr/lib/opkg/info/luci-app-passwall.control"
test -f "${rootfs_dir}/usr/lib/opkg/info/xray-core.control"
test -f "${rootfs_dir}/usr/lib/opkg/info/luci-theme-argon.control"
test -d "${rootfs_dir}/www/luci-static/argon"

echo "PassWall, Xray and Argon were installed into ${rootfs_dir}"
