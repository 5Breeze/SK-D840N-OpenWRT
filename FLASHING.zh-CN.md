# SK-D840N OpenWrt 24.10.8 + PassWall 刷机说明

## 固件内容

- 保留原项目适配的 Bootloader、Linux 6.6.144 内核、DTB 和网口配置。
- OpenWrt 24.10.8（`armsr/armv8`，`aarch64_generic`）。
- `opkg` 与 LuCI“软件包”页面，可继续安装兼容的 `.ipk`。
- LuCI Argon 现代主题与简体中文界面。
- PassWall（nftables 透明代理）及 Xray Core。

## 文件

- `boot.bin`：Bootloader。
- `uImage`：内核。
- `board.dtb`：设备树。
- `rootfs.jffs2`：包含 LuCI、IPK 包管理器和 PassWall 的根文件系统。
- `openwrt-24.10.8-sk-d840n-sysupgrade.tar`：后续在 LuCI 或命令行升级的固件包。
- `tftp.py` / `requirements.txt`：TFTP 传输工具。
- `ipk/`：本次构建生成的 PassWall、Xray 和 Argon IPK 备份。

## 重要警告

刷写 Bootloader 有变砖风险。仅在硬件版本与原项目 README 所列 V2024/V2025 一致、串口工作正常且具备救砖能力时操作。升级已有同版本固件时，通常只刷 `rootfs.jffs2` 即可；不要无故重复刷写 Bootloader。

## TFTP 刷写

电脑设置静态地址 `192.168.1.40`，进入固件解压目录并启动：

```text
python -m pip install -r requirements.txt
python tftp.py
```

串口波特率设为 115200，启动时按 `u` 停在 U-Boot。

全新刷写按原项目分区布局执行：

```text
tftpboot 0x88000000 192.168.1.40:boot.bin
nand erase 0x00000000 0x00200000
nand write 0x88000000 0x00000000 ${filesize}

tftpboot 0x88000000 192.168.1.40:uImage
nand erase 0x00200000 0x00800000
nand write 0x88000000 0x00200000 ${filesize}

tftpboot 0x88000000 192.168.1.40:board.dtb
nand erase 0x00a00000 0x00100000
nand write 0x88000000 0x00a00000 ${filesize}

nand read 0x88000000 0x04800000 0x00400000
nand erase 0x00b00000 0x00400000
nand write 0x88000000 0x00b00000 0x00400000

tftpboot 0x88000000 192.168.1.40:rootfs.jffs2
nand erase 0x00f00000 0x0f100000
nand write 0x88000000 0x00f00000 ${filesize}
reset
```

只更新 rootfs：

```text
tftpboot 0x88000000 192.168.1.40:rootfs.jffs2
nand erase 0x00f00000 0x0f100000
nand write 0x88000000 0x00f00000 ${filesize}
reset
```

首次启动后访问 `http://192.168.1.1`。PassWall 位于 LuCI 的“服务”菜单；固件不预置任何节点或订阅。

## Sysupgrade 后续升级

原仓库固件没有 SK-D840N 专用的 sysupgrade 平台脚本，因此第一次安装本构建版仍须通过 TFTP 刷写 `rootfs.jffs2`。启动一次本构建版后，今后的版本即可使用 sysupgrade。

LuCI：系统 → 备份/升级 → 刷写新的固件，上传 `openwrt-24.10.8-sk-d840n-sysupgrade.tar`。

命令行先做只读校验：

```text
sysupgrade -T /tmp/openwrt-24.10.8-sk-d840n-sysupgrade.tar
```

保留配置升级：

```text
sysupgrade /tmp/openwrt-24.10.8-sk-d840n-sysupgrade.tar
```

不保留配置：

```text
sysupgrade -n /tmp/openwrt-24.10.8-sk-d840n-sysupgrade.tar
```

升级脚本会校验设备兼容标识、包内 SHA-256、文件大小，以及 `kernel`、`dtb`、`root` 三个 MTD 分区的名称和容量。它只写入这三个分区，不会写入 Bootloader 或 param 分区。切勿使用 `-F` 绕过校验。

## 安装其他 IPK

网页：LuCI → 系统 → 软件包 → 上传软件包。

命令行：

```text
opkg update
opkg install /tmp/example.ipk
```

只安装 `aarch64_generic`、`all`，或与本固件 OpenWrt 24.10.8 / Linux 6.6.144 ABI 完全匹配的 IPK。内核模块必须来自固件配置的 `openwrt_kmods` 软件源，不能混用其他版本。
