#!/usr/bin/env bash
set -euo pipefail

# Build PassWall for the exact OpenWrt userspace/kernel ABI used by SK-D840N,
# then install the resulting IPKs into the repository rootfs.

BUILD_SCRIPT_REVISION="20260831.2-firewall3-iptables"
echo "[build] build_passwall_rootfs.sh revision: ${BUILD_SCRIPT_REVISION}"

OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.8}"
SDK_FILE="openwrt-sdk-${OPENWRT_VERSION}-armsr-armv8_gcc-13.3.0_musl.Linux-x86_64.tar.zst"
SDK_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/armsr/armv8/${SDK_FILE}"
PASSWALL_REPO="${PASSWALL_REPO:-https://github.com/Openwrt-Passwall/openwrt-passwall.git}"
PASSWALL_PACKAGES_REPO="${PASSWALL_PACKAGES_REPO:-https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git}"
ARGON_REPO="${ARGON_REPO:-https://github.com/jerrykuku/luci-theme-argon.git}"
ARGON_CONFIG_REPO="${ARGON_CONFIG_REPO:-https://github.com/jerrykuku/luci-app-argon-config.git}"
# Pin upstream inputs so a future main-branch update cannot silently break an
# otherwise identical firmware build. Override both REPO and REF together when
# intentionally testing newer upstream code.
PASSWALL_REF="${PASSWALL_REF:-bbd098938427249f06f644341bfb916bad5cab5c}"
PASSWALL_PACKAGES_REF="${PASSWALL_PACKAGES_REF:-b2d6f2384de1b50c6e7626a4e976cda42be15966}"
ARGON_REF="${ARGON_REF:-ddefe5f05ca334dba10d2d65d25ebf14e986ee88}"
ARGON_CONFIG_REF="${ARGON_CONFIG_REF:-3e099a37c3f71d0de677f1b6b0f4bffd57d91dac}"
# OpenWrt 24.10 ships Go 1.23.x. Newer Xray releases require Go 1.24+
# (26.7.28 requires 1.26), so use the newest known Go 1.23-compatible release.
XRAY_VERSION="${XRAY_VERSION:-25.2.21}"
XRAY_HASH="${XRAY_HASH:-a565db518d2da12fabb74e123d9bf2bdbc34420b81373938f8fcbc7004fda3ba}"

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${BUILD_DIR:-${repo_dir}/.build-passwall}"
download_dir="${build_dir}/downloads"
sdk_dir="${build_dir}/sdk"
rootfs_dir="${repo_dir}/rootfs"

rm -rf "${build_dir}"
mkdir -p "${download_dir}" "${sdk_dir}"

test -x "${rootfs_dir}/bin/opkg"
test -d "${rootfs_dir}/usr/lib/opkg/info"
test "$(readlink "${rootfs_dir}/var")" = "tmp" || {
    echo "rootfs/var must be the original relative symlink to tmp" >&2
    exit 1
}
test "$(readlink "${rootfs_dir}/etc/resolv.conf")" = "/tmp/resolv.conf" || {
    echo "rootfs/etc/resolv.conf must be the original OpenWrt symlink" >&2
    exit 1
}

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

clone_ref() {
    local repository="$1"
    local reference="$2"
    local destination="$3"

    git init --quiet "${destination}"
    git -C "${destination}" remote add origin "${repository}"
    git -C "${destination}" fetch --quiet --depth 1 origin "${reference}"
    git -C "${destination}" checkout --quiet --detach FETCH_HEAD
}

curl --fail --location --retry 5 --silent --show-error \
    --output "${download_dir}/${SDK_FILE}" "${SDK_URL}"
tar --zstd -xf "${download_dir}/${SDK_FILE}" -C "${sdk_dir}" --strip-components=1

clone_ref "${PASSWALL_REPO}" "${PASSWALL_REF}" \
    "${sdk_dir}/package/passwall-luci"
clone_ref "${PASSWALL_PACKAGES_REPO}" "${PASSWALL_PACKAGES_REF}" \
    "${sdk_dir}/package/passwall-packages"
clone_ref "${ARGON_REPO}" "${ARGON_REF}" \
    "${sdk_dir}/package/luci-theme-argon"
clone_ref "${ARGON_CONFIG_REPO}" "${ARGON_CONFIG_REF}" \
    "${sdk_dir}/package/luci-app-argon-config"

# The checked-in image uses a vendor 4.19 kernel. OpenWrt's default firewall4
# package is built for the SDK's 6.6 kernel and its nftables modules cannot be
# loaded by that kernel, so build the legacy firewall from this repository.
cp -a "${repo_dir}/package/firewall" "${sdk_dir}/package/firewall"

xray_makefile="${sdk_dir}/package/passwall-packages/xray-core/Makefile"
test -f "${xray_makefile}"
sed -i \
    -e "s/^PKG_VERSION:=.*/PKG_VERSION:=${XRAY_VERSION}/" \
    -e "s/^PKG_HASH:=.*/PKG_HASH:=${XRAY_HASH}/" \
    "${xray_makefile}"
grep -qx "PKG_VERSION:=${XRAY_VERSION}" "${xray_makefile}"
grep -qx "PKG_HASH:=${XRAY_HASH}" "${xray_makefile}"

cd "${sdk_dir}"
run_quiet "Update OpenWrt feeds" "${build_dir}/feeds-update.log" \
    ./scripts/feeds update -a
run_quiet "Install OpenWrt feeds" "${build_dir}/feeds-install.log" \
    ./scripts/feeds install -a

# Keep the image practical for 256 MiB NAND: legacy iptables + Xray provides
# the PassWall path compatible with the device's vendor 4.19 kernel.
cat >> .config <<'EOF'
CONFIG_ALL_NONSHARED=n
CONFIG_ALL_KMODS=n
CONFIG_ALL=n
CONFIG_AUTOREMOVE=n
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_firewall=m
CONFIG_PACKAGE_firewall4=n
CONFIG_PACKAGE_nftables-json=n
CONFIG_PACKAGE_kmod-nft-core=n
CONFIG_PACKAGE_kmod-nft-fib=n
CONFIG_PACKAGE_kmod-nft-nat=n
CONFIG_PACKAGE_kmod-nft-offload=n
CONFIG_PACKAGE_xtables-legacy=m
CONFIG_PACKAGE_iptables-zz-legacy=m
CONFIG_PACKAGE_ip6tables-zz-legacy=m
CONFIG_PACKAGE_luci-app-passwall=m
CONFIG_PACKAGE_luci-app-passwall_Iptables_Transparent_Proxy=y
# CONFIG_PACKAGE_luci-app-passwall_Nftables_Transparent_Proxy is not set
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

# Compile PassWall's non-standard runtime dependencies explicitly. Do not use
# broad download or package/compile targets here: an SDK can select target
# defaults such as base-files and mac80211, which are unrelated to this rootfs
# overlay and may require a full firmware build tree. Each precise compile
# target downloads its own source prerequisites.
for package in chinadns-ng dns2socks ipt2socks microsocks tcping; do
    run_quiet "Compile ${package}" "${build_dir}/${package}-compile.log" \
        make -j2 "package/passwall-packages/${package}/compile"
done

# Build the large Go package separately. This avoids interleaved parallel
# output and gives a focused verbose retry if its toolchain requirements ever
# change again.
if ! run_quiet "Compile Xray ${XRAY_VERSION}" "${build_dir}/xray-compile.log" \
    make -j2 package/passwall-packages/xray-core/compile; then
    echo "::group::Xray detailed retry"
    echo "[build] Xray failed; retrying with -j1 V=sc for diagnostics..." >&2
    set +e
    make -j1 V=sc package/passwall-packages/xray-core/compile \
        >"${build_dir}/xray-compile-verbose.log" 2>&1
    xray_status=$?
    set -e
    tail -n 350 "${build_dir}/xray-compile-verbose.log" >&2 || true
    echo "::endgroup::"
    if [ "${xray_status}" -ne 0 ]; then
        exit "${xray_status}"
    fi
    echo "[build] Xray verbose retry succeeded"
fi

run_quiet "Compile PassWall LuCI application" "${build_dir}/passwall-luci-compile.log" \
    make -j2 package/passwall-luci/luci-app-passwall/compile
run_quiet "Compile Argon theme" "${build_dir}/argon-theme-compile.log" \
    make -j2 package/luci-theme-argon/compile
run_quiet "Compile Argon configuration" "${build_dir}/argon-config-compile.log" \
    make -j2 package/luci-app-argon-config/compile
run_quiet "Compile firewall3" "${build_dir}/firewall-compile.log" \
    make -j2 package/firewall/compile
run_quiet "Compile legacy iptables" "${build_dir}/iptables-compile.log" \
    make -j2 package/network/utils/iptables/compile

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
    luci-app-passwall luci-theme-argon luci-app-argon-config \
    firewall xtables-legacy iptables-zz-legacy ip6tables-zz-legacy \
    libip4tc libip6tc libiptext libiptext6 libxtables; do
    copy_ipk "${package}"
done
copy_ipk luci-i18n-passwall-zh-cn no
copy_ipk luci-i18n-argon-config-zh-cn no

# qemu-user-static lets the CI host run the rootfs' native aarch64 opkg. Using
# --offline-root also prevents package post-install scripts from starting
# router services inside the build host.
qemu_bin="$(command -v qemu-aarch64-static)"
test -n "${qemu_bin}"
mkdir -p "${rootfs_dir}/tmp/lock" "${rootfs_dir}/tmp/opkg-lists"
chmod 1777 "${rootfs_dir}/tmp/lock"
cp "${qemu_bin}" "${rootfs_dir}/usr/bin/qemu-aarch64-static"
cp /etc/resolv.conf "${rootfs_dir}/tmp/resolv.conf"

# Use the canonical OpenWrt CDN during the build. The repository's Tsinghua
# mirror remains useful in China, but its TLS endpoint is not consistently
# compatible with the older mbedTLS client in OpenWrt 24.10.
test -s "${rootfs_dir}/etc/opkg/distfeeds.conf.default"
cp "${rootfs_dir}/etc/opkg/distfeeds.conf.default" \
    "${rootfs_dir}/etc/opkg/distfeeds.conf"

cleanup_chroot() {
    local mount_dir

    for mount_dir in sys proc dev; do
        if mountpoint -q "${rootfs_dir}/${mount_dir}"; then
            sudo umount "${rootfs_dir}/${mount_dir}" || \
                sudo umount -l "${rootfs_dir}/${mount_dir}" || true
        fi
    done
    sudo rm -f -- \
        "${rootfs_dir}/usr/bin/qemu-aarch64-static" \
        "${rootfs_dir}/tmp/resolv.conf" \
        "${rootfs_dir}/tmp/lock/opkg.lock"
    sudo rm -rf -- \
        "${ipk_dir}" \
        "${rootfs_dir}/tmp/opkg-lists" \
        "${rootfs_dir}/tmp/usr" || true
    sudo find "${rootfs_dir}/tmp" -mindepth 1 -maxdepth 1 \
        -type d -name 'opkg-*' -exec rm -rf -- {} + || true
    sudo rmdir "${rootfs_dir}/tmp/lock" 2>/dev/null || true
    return 0
}
trap cleanup_chroot EXIT

# The checked-in rootfs intentionally has empty /dev, /proc and /sys. Bind the
# host runtime views while using opkg; without /dev/urandom the OpenWrt TLS
# client reports a generic SSL failure for every HTTPS package feed.
sudo mount --bind /dev "${rootfs_dir}/dev"
sudo mount --bind /proc "${rootfs_dir}/proc"
sudo mount --bind /sys "${rootfs_dir}/sys"
test -c "${rootfs_dir}/dev/urandom"
test -r "${rootfs_dir}/proc/meminfo"

chroot_opkg() {
    sudo chroot "${rootfs_dir}" /usr/bin/qemu-aarch64-static \
        /bin/opkg --offline-root / "$@"
}

chroot_opkg update

# PassWall needs dnsmasq-full. It intentionally replaces the smaller dnsmasq
# package from the base rootfs. Remove the generic firewall4 stack first: its
# package metadata and init script otherwise win over the legacy firewall.
chroot_opkg remove dnsmasq || true
chroot_opkg remove --force-depends firewall4
chroot_opkg remove --force-depends nftables-json kmod-nft-nat kmod-nft-socket \
    kmod-nft-tproxy kmod-nft-offload kmod-nft-fib kmod-nft-core || true
test ! -e "${rootfs_dir}/usr/lib/opkg/info/firewall4.control"
chroot_opkg install \
    dnsmasq-full coreutils coreutils-base64 coreutils-nohup coreutils-timeout \
    curl ip-full libuci-lua lua luci-compat luci-lib-jsonc \
    lyaml resolveip unzip

mapfile -t local_ipks < <(
    find "${ipk_dir}" -maxdepth 1 -type f -name '*.ipk' \
        -printf '/tmp/passwall-ipks/%f\n' | sort
)
# The SDK records its own 6.6 kernel package as a dependency of iptables. The
# vendor 4.19 kernel already supplies the matching netfilter modules, so do
# not let that SDK-only dependency block installation into this rootfs.
chroot_opkg install --force-depends "${local_ipks[@]}"
chroot_opkg install \
    luci-i18n-base-zh-cn luci-i18n-package-manager-zh-cn \
    luci-i18n-firewall-zh-cn || true

cleanup_chroot
trap - EXIT

# Argon remains selectable in LuCI, and is the default on first boot.
sudo sed -i 's#option mediaurlbase /luci-static/[^[:space:]]*#option mediaurlbase /luci-static/argon#' \
    "${rootfs_dir}/etc/config/luci"

test -x "${rootfs_dir}/bin/opkg"
test -f "${rootfs_dir}/usr/lib/opkg/info/luci-app-package-manager.control"
test -f "${rootfs_dir}/usr/lib/opkg/info/luci-app-passwall.control"
test -f "${rootfs_dir}/usr/lib/opkg/info/xray-core.control"
test -f "${rootfs_dir}/usr/lib/opkg/info/luci-theme-argon.control"
test -d "${rootfs_dir}/www/luci-static/argon"

echo "PassWall, Xray and Argon were installed into ${rootfs_dir}"
