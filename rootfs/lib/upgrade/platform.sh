#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

# SK-D840N NAND layout (do not modify boot/param from sysupgrade):
#   boot   0x00000000..0x001fffff
#   kernel 0x00200000..0x009fffff
#   dtb    0x00a00000..0x00afffff
#   param  0x00b00000..0x00efffff
#   root   0x00f00000..0x0fffffff

REQUIRE_IMAGE_METADATA=1
RAMFS_COPY_BIN="sha256sum"

SKD_SYSUPGRADE_DIR="sysupgrade-sk-d840n"
SKD_KERNEL_MAX=$((0x00800000))
SKD_DTB_MAX=$((0x00100000))
SKD_ROOTFS_MAX=$((0x0f100000))

skd_extract_member() {
	local image="$1"
	local member="$2"
	local destination="$3"

	tar -xf "$image" -O "${SKD_SYSUPGRADE_DIR}/${member}" > "$destination"
}

skd_mtd_size() {
	local wanted="$1"
	local dev size erase name

	while read -r dev size erase name; do
		name="${name#\"}"
		name="${name%\"}"
		[ "$name" = "$wanted" ] && {
			echo $((0x$size))
			return 0
		}
	done < /proc/mtd
	return 1
}

skd_check_partition() {
	local name="$1"
	local expected="$2"
	local actual

	actual="$(skd_mtd_size "$name")" || {
		v "Required MTD partition '$name' was not found"
		return 1
	}
	[ "$actual" -eq "$expected" ] || {
		v "MTD partition '$name' has unexpected size $actual (expected $expected)"
		return 1
	}
}

platform_check_image() {
	local image="$1"
	local board="$(board_name)"
	local check_dir=/tmp/skd-sysupgrade-check
	local member size max

	[ "$#" -eq 1 ] || return 1
	[ "$board" = "zte,133" ] || {
		v "This image is only for SK-D840N (zte,133), current board is $board"
		return 1
	}

	rm -rf "$check_dir"
	mkdir -p "$check_dir"
	for member in CONTROL sha256sums uImage board.dtb rootfs.jffs2; do
		skd_extract_member "$image" "$member" "$check_dir/$member" || {
			v "Missing or unreadable sysupgrade member: $member"
			rm -rf "$check_dir"
			return 1
		}
	done

	grep -qx 'BOARD=zte,133' "$check_dir/CONTROL" || {
		v "Invalid SK-D840N sysupgrade control file"
		rm -rf "$check_dir"
		return 1
	}

	(
		cd "$check_dir" || exit 1
		sha256sum -c sha256sums
	) || {
		v "Sysupgrade payload checksum verification failed"
		rm -rf "$check_dir"
		return 1
	}

	for member in uImage board.dtb rootfs.jffs2; do
		size="$(wc -c < "$check_dir/$member")"
		case "$member" in
			uImage) max="$SKD_KERNEL_MAX" ;;
			board.dtb) max="$SKD_DTB_MAX" ;;
			rootfs.jffs2) max="$SKD_ROOTFS_MAX" ;;
		esac
		[ "$size" -le "$max" ] || {
			v "$member is too large: $size bytes (maximum $max)"
			rm -rf "$check_dir"
			return 1
		}
	done

	# Refuse to run if this is not the exact raw-NAND layout used by the repo.
	skd_check_partition kernel "$SKD_KERNEL_MAX" || return 1
	skd_check_partition dtb "$SKD_DTB_MAX" || return 1
	skd_check_partition root "$SKD_ROOTFS_MAX" || return 1

	rm -rf "$check_dir"
	return 0
}

platform_do_upgrade() {
	local image="$1"
	local upgrade_dir=/tmp/skd-sysupgrade
	local member

	rm -rf "$upgrade_dir"
	mkdir -p "$upgrade_dir"
	for member in uImage board.dtb rootfs.jffs2; do
		skd_extract_member "$image" "$member" "$upgrade_dir/$member" || exit 1
	done

	# Re-check the physical layout from ramfs immediately before erasing NAND.
	skd_check_partition kernel "$SKD_KERNEL_MAX" || exit 1
	skd_check_partition dtb "$SKD_DTB_MAX" || exit 1
	skd_check_partition root "$SKD_ROOTFS_MAX" || exit 1

	sync
	v "Writing SK-D840N device tree to MTD 'dtb'"
	mtd write "$upgrade_dir/board.dtb" dtb || exit 1

	v "Writing SK-D840N JFFS2 root filesystem to MTD 'root'"
	if [ -n "$UPGRADE_BACKUP" ]; then
		mtd $MTD_ARGS $MTD_CONFIG_ARGS -j "$UPGRADE_BACKUP" \
			write "$upgrade_dir/rootfs.jffs2" root || exit 1
	else
		mtd $MTD_ARGS write "$upgrade_dir/rootfs.jffs2" root || exit 1
	fi

	# Kernel is intentionally last: bootloader and param are never touched.
	v "Writing SK-D840N kernel to MTD 'kernel'"
	mtd write "$upgrade_dir/uImage" kernel || exit 1
	sync
}
