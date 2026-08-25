#!/usr/bin/env bash
set -Eeuo pipefail

# Build an ImmortalWrt userland and package it for the vendor SK-D840N 4.19 kernel.
# This script intentionally does not use the generic armsr kernel or DTB as output.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK_DIR=${WORK_DIR:-"$PWD"}
IMMORTAL_DIR=${IMMORTAL_DIR:-"$WORK_DIR/immortalwrt"}
SK_SOURCE=${SK_SOURCE:-"$WORK_DIR/SK-D840N-OpenWRT"}
BRANCH=${BRANCH:-openwrt-24.10}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}
ROOTFS_PART_SIZE=${ROOTFS_PART_SIZE:-$((0x0f100000))}
DIST_DIR=${DIST_DIR:-"$WORK_DIR/dist"}

info() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null || die "git is required"
command -v make >/dev/null || die "make is required; run this script on Linux"
command -v rsync >/dev/null || die "rsync is required"
command -v mkfs.jffs2 >/dev/null || die "mtd-utils (mkfs.jffs2) is required"
command -v sha256sum >/dev/null || die "sha256sum is required"

if [[ ! -d "$SK_SOURCE/.git" ]]; then
    info "Cloning the hardware reference repository"
    git clone --depth 1 https://github.com/huxiangjs/SK-D840N-OpenWRT.git "$SK_SOURCE"
fi

if [[ ! -d "$IMMORTAL_DIR/.git" ]]; then
    info "Cloning ImmortalWrt $BRANCH"
    git clone -b "$BRANCH" --single-branch --filter=blob:none \
        https://github.com/immortalwrt/immortalwrt.git "$IMMORTAL_DIR"
fi

[[ -f "$SK_SOURCE/binary/uImage" ]] || die "missing $SK_SOURCE/binary/uImage"
[[ -f "$SK_SOURCE/binary/board.dtb" ]] || die "missing $SK_SOURCE/binary/board.dtb"
[[ -d "$SK_SOURCE/rootfs/lib/modules/4.19.136+" ]] || die "missing vendor 4.19.136+ modules"

cd "$IMMORTAL_DIR"
info "Updating and installing feeds"
./scripts/feeds update -a
./scripts/feeds install -a

info "Selecting ARM64 generic userland target"
cp "$SCRIPT_DIR/immortalwrt.config" .config
make defconfig
grep -q '^CONFIG_TARGET_armsr_armv8_DEVICE_generic=y$' .config \
    || die "the selected ImmortalWrt tree does not expose the armsr/armv8 generic device"

info "Compiling ImmortalWrt (the generic kernel output is not used)"
make -j"$JOBS" world

ROOTFS_DIR=$(find build_dir -maxdepth 2 -type d -name 'root-*' | sort | tail -n 1)
[[ -n "$ROOTFS_DIR" && -d "$ROOTFS_DIR" ]] || die "cannot locate the staged rootfs under build_dir"

info "Merging SK-D840N vendor runtime files"
VENDOR_ROOTFS="$SK_SOURCE/rootfs"
mkdir -p "$ROOTFS_DIR/etc/board.d" "$ROOTFS_DIR/etc/modules.d" \
    "$ROOTFS_DIR/etc/modules-boot.d" "$ROOTFS_DIR/lib/modules"

# The board name comes from the original DTB, which remains in use.
for file in etc/init.d/boot etc/board.d/02_network etc/board.d/99-default_network \
            sbin/if_addr sbin/eth_setup sbin/devmem2; do
    install -D -m 0755 "$VENDOR_ROOTFS/$file" "$ROOTFS_DIR/$file"
done

# Keep the vendor module ordering and both the 4.19 module tree and its SLC subdir.
rsync -a "$VENDOR_ROOTFS/etc/modules.d/." "$ROOTFS_DIR/etc/modules.d/"
rsync -a "$VENDOR_ROOTFS/etc/modules-boot.d/." "$ROOTFS_DIR/etc/modules-boot.d/"
rsync -a "$VENDOR_ROOTFS/lib/modules/4.19.136+/." "$ROOTFS_DIR/lib/modules/4.19.136+/"

# Optional user-provided files (currently the Argon default-theme UCI hook).
if [[ -d "$SCRIPT_DIR/overlay" ]]; then
    rsync -a "$SCRIPT_DIR/overlay/." "$ROOTFS_DIR/"
    chmod 0755 "$ROOTFS_DIR/etc/uci-defaults/99-skd840n-luci" 2>/dev/null || true
fi

# The stock script mounts this device's raw JFFS2 partition as /dev/mtdblock4.
# Do not copy the vendor repository's symlink placeholder for /etc/config/fstab.
rm -f "$ROOTFS_DIR/etc/config/fstab"
printf '%s\n' '# SK-D840N uses the vendor boot/mount layout.' > "$ROOTFS_DIR/etc/config/fstab"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/rootfs.jffs2" "$DIST_DIR/boot.bin" "$DIST_DIR/uImage" "$DIST_DIR/board.dtb"
info "Creating JFFS2 rootfs"
mkfs.jffs2 -d "$ROOTFS_DIR" -l -n -s 0x800 -e 0x20000 -o "$DIST_DIR/rootfs.jffs2"

ROOTFS_BYTES=$(stat -c '%s' "$DIST_DIR/rootfs.jffs2")
(( ROOTFS_BYTES <= ROOTFS_PART_SIZE )) || die "rootfs.jffs2 is $ROOTFS_BYTES bytes, larger than partition limit $ROOTFS_PART_SIZE"

cp -a "$SK_SOURCE/binary/boot.bin" "$DIST_DIR/boot.bin"
cp -a "$SK_SOURCE/binary/uImage" "$DIST_DIR/uImage"
cp -a "$SK_SOURCE/binary/board.dtb" "$DIST_DIR/board.dtb"

cp .config "$DIST_DIR/immortalwrt.full.config"
{
    printf 'ImmortalWrt branch: %s\n' "$BRANCH"
    printf 'ImmortalWrt commit: %s\n' "$(git rev-parse HEAD)"
    printf 'SK-D840N commit:    %s\n' "$(git -C "$SK_SOURCE" rev-parse HEAD)"
    printf 'Rootfs bytes:       %s\n' "$ROOTFS_BYTES"
    printf 'Partition limit:    %s\n' "$ROOTFS_PART_SIZE"
    printf 'Build UTC:          %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} > "$DIST_DIR/BUILD-INFO.txt"

(
    cd "$DIST_DIR"
    sha256sum rootfs.jffs2 boot.bin uImage board.dtb > SHA256SUMS
)

info "Build complete"
printf 'rootfs.jffs2: %s bytes\n' "$ROOTFS_BYTES"
printf 'artifacts:    %s\n' "$DIST_DIR"
printf 'kernel/DTB:   vendor files copied unchanged\n'
