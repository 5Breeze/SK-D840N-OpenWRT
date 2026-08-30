#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-${repo_dir}/openwrt-24.10.8-sk-d840n-sysupgrade.tar}"
work_dir="$(mktemp -d)"
payload_dir="${work_dir}/sysupgrade-sk-d840n"
rootfs_dir="${repo_dir}/rootfs"

cleanup() {
    rm -rf "${work_dir}"
    sudo rm -f \
        "${rootfs_dir}/usr/bin/qemu-aarch64-static" \
        "${rootfs_dir}/tmp/sk-d840n-sysupgrade.tar" \
        "${rootfs_dir}/tmp/sk-d840n-sysupgrade.meta"
}
trap cleanup EXIT

for file in binary/uImage binary/board.dtb rootfs.jffs2; do
    test -s "${repo_dir}/${file}" || {
        echo "Missing build input: ${file}" >&2
        exit 1
    }
done

mkdir -p "${payload_dir}"
cp "${repo_dir}/binary/uImage" "${payload_dir}/uImage"
cp "${repo_dir}/binary/board.dtb" "${payload_dir}/board.dtb"
cp "${repo_dir}/rootfs.jffs2" "${payload_dir}/rootfs.jffs2"

printf '%s\n' \
    'BOARD=zte,133' \
    'MODEL=SK-D840N' \
    'FORMAT_VERSION=1' \
    'KERNEL_PARTITION=kernel' \
    'DTB_PARTITION=dtb' \
    'ROOTFS_PARTITION=root' > "${payload_dir}/CONTROL"

(
    cd "${payload_dir}"
    sha256sum uImage board.dtb rootfs.jffs2 > sha256sums
)

# Use a plain ustar archive: BusyBox tar can extract it after sysupgrade pivots
# to ramfs, and fwtool metadata is appended below for LuCI compatibility checks.
tar --format=ustar -C "${work_dir}" -cf "${work_dir}/sk-d840n-sysupgrade.tar" \
    sysupgrade-sk-d840n

cat > "${work_dir}/sk-d840n-sysupgrade.meta" <<'EOF'
{
  "metadata_version": "1.1",
  "compat_version": "1.0",
  "supported_devices": ["zte,133"],
  "version": {
    "dist": "OpenWrt",
    "version": "24.10.8",
    "revision": "r29233-443ec4032a",
    "target": "armsr/armv8",
    "board": "armv8"
  }
}
EOF

# fwtool in this rootfs is aarch64. Run it through qemu-user-static to append
# standard OpenWrt metadata, so LuCI accepts the image without -F.
qemu_bin="$(command -v qemu-aarch64-static)"
sudo cp "${qemu_bin}" "${rootfs_dir}/usr/bin/qemu-aarch64-static"
sudo cp "${work_dir}/sk-d840n-sysupgrade.tar" \
    "${rootfs_dir}/tmp/sk-d840n-sysupgrade.tar"
sudo cp "${work_dir}/sk-d840n-sysupgrade.meta" \
    "${rootfs_dir}/tmp/sk-d840n-sysupgrade.meta"
sudo chroot "${rootfs_dir}" /usr/bin/qemu-aarch64-static \
    /usr/bin/fwtool -I /tmp/sk-d840n-sysupgrade.meta \
    /tmp/sk-d840n-sysupgrade.tar
sudo cp "${rootfs_dir}/tmp/sk-d840n-sysupgrade.tar" "${output}"
sudo chown "$(id -u):$(id -g)" "${output}"

test -s "${output}"
echo "Created ${output}"
