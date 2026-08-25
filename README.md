# SK-D840N：ImmortalWrt 用户空间构建

## 完整教程索引

- [01：本地 Linux 与 GitHub Actions 编译](docs/01-build.md)
- [02：Argon 现代 UI、插件与自定义文件](docs/02-ui-and-packages.md)
- [03：首次刷机、仅升级 rootfs 与恢复](docs/03-flash-and-recovery.md)

如果只想快速完成：把本目录所有文件原样放进 fork 后的 `SK-D840N-OpenWRT` 仓库根目录，在 GitHub 的 **Actions** 页面运行 **Build SK-D840N ImmortalWrt rootfs**，下载产物后严格按照第 03 篇教程刷写。

这个目录提供一条可启动性优先的构建路径：

- 使用 ImmortalWrt `openwrt-24.10` 分支编译 ARM64 用户空间、LuCI 和软件包；
- 继续使用 SK-D840N 仓库里已经验证过的厂商 `boot.bin`、`uImage`、`board.dtb`；
- 把厂商 4.19.136 内核模块、`if_addr`、`eth_setup` 以及 `zte,133` 的网络初始化脚本合并进新 rootfs；
- 按原仓库的 JFFS2 参数生成 `rootfs.jffs2`。

这不是把设备改造成主线 `armsr` 设备。SK-D840N 的 DTB 是 `ZTE 133`，并包含 `zxic,zx-*` 私有外设及 PON 驱动；ImmortalWrt 当前没有这个 SoC 的主线 target。因此不能直接刷 ImmortalWrt 生成的通用 kernel、DTB 或 sysupgrade 镜像。

## 构建环境

请在 Debian 11/12 或 Ubuntu 22.04/24.04 的 x86_64 Linux 中执行，不能在 Windows PowerShell 里直接编译。ImmortalWrt 官方要求大小写敏感的文件系统、至少约 4 GB 内存和 25 GB 可用磁盘空间。

```sh
sudo apt update
sudo apt install -y ack antlr3 asciidoc autoconf automake autopoint binutils bison \
  build-essential bzip2 ccache clang cmake cpio curl device-tree-compiler ecj fastjar \
  flex gawk gettext gcc-multilib g++-multilib git libgnutls28-dev gperf haveged help2man \
  intltool lib32gcc-s1 libc6-dev-i386 libelf-dev libglib2.0-dev libgmp3-dev \
  libltdl-dev libmpc-dev libmpfr-dev libncurses-dev libpython3-dev libreadline-dev \
  libssl-dev libtool libyaml-dev libz-dev lld llvm make mkisofs nano ninja-build \
  p7zip-full patch pkgconf python3 python3-pip python3-ply python3-docutils \
  python3-pyelftools qemu-utils rsync squashfs-tools subversion swig texinfo \
  uglifyjs unzip wget xxd zstd mtd-utils
```

## 构建

把本目录的脚本放在一个工作目录中运行。默认会把源码放在当前目录的 `immortalwrt` 和 `SK-D840N-OpenWRT` 子目录；也可以通过环境变量指定已有的源码目录。

```sh
chmod +x build-immortalwrt-rootfs.sh
./build-immortalwrt-rootfs.sh
```

常用变量：

```sh
JOBS=8 ./build-immortalwrt-rootfs.sh
IMMORTAL_DIR=/data/immortalwrt SK_SOURCE=/data/SK-D840N-OpenWRT \
  ./build-immortalwrt-rootfs.sh
```

成功后，生成物位于 `dist/`：

```text
rootfs.jffs2       # 唯一需要替换的分区镜像
boot.bin           # 原仓库文件，脚本只是复制用于备份
uImage             # 原仓库文件，脚本只是复制用于备份
board.dtb          # 原仓库文件，脚本只是复制用于备份
```

## 现代 LuCI 和插件

当前配置已经预选 Argon 主题、Argon 设置页、DDNS、HTTPS DNS Proxy 和 ttyd，并通过 `overlay/etc/uci-defaults/99-skd840n-luci` 将 Argon 设为首次启动时的默认主题。Argon 官方说明其 master 分支面向较新的 OpenWrt/ImmortalWrt LuCI；ImmortalWrt 的 LuCI feed 也包含 Argon 主题和 Argon 配置应用。[Argon 项目说明](https://github.com/jerrykuku/luci-theme-argon)，[ImmortalWrt LuCI feed](https://github.com/immortalwrt/luci)

要增加普通插件，编辑 `immortalwrt.config`，例如：

```text
CONFIG_PACKAGE_luci-app-statistics=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-adblock-fast=y
```

然后删除 ImmortalWrt 源码目录中的旧 `.config`，重新运行构建脚本；脚本会重新执行 `feeds update/install`、`make defconfig` 和 `make world`。不要一次加入多个代理/容器套件，先单独编译验证空间和依赖。

`luci-app-openclash`、`luci-app-passwall`、`luci-app-homeproxy`、SQM 等插件可能依赖 TUN、nftables、透明代理或特定内核模块。由于本设备继续使用厂商 4.19 内核，ImmortalWrt 生成的 6.6 `kmod-*` 不能加载；这类插件即使 LuCI 页面能编译出来，核心转发功能也可能不可用。ImmortalWrt 社区也记录过安装 Passwall 时因 kernel 版本依赖不匹配而失败的情况。[相关说明](https://github.com/immortalwrt/immortalwrt/discussions/1392)

首次刷机仍然使用原项目 README 中的 U-Boot 命令；只把第 6 步的 `rootfs.jffs2` 换成 `dist/rootfs.jffs2`。不要把 `bin/targets/armsr/armv8/` 下的 kernel、DTB、combined 或 sysupgrade 文件刷入 SK-D840N。

刷写前请先通过串口确认当前分区布局，并保留原始 `boot.bin`、`uImage`、`board.dtb`。JFFS2 参数固定为 NAND 页大小 `0x800`、擦除块 `0x20000`，rootfs 分区上限为 `0x0f100000`；脚本会在超过上限时中止。

## 风险与验证

该方案依赖厂商 4.19 内核，ImmortalWrt 编译出的 6.6 内核模块不能加载，所以脚本保留厂商模块并避免把通用内核刷入设备。首次启动建议接串口，观察：

```sh
uname -a
cat /tmp/sysinfo/board_name
logread | grep -E 'kmod|netdriver|np_133|gpon|switch'
ip link
```

预期 board name 为 `zte,133`，网口由原厂 `eth_setup` 初始化。若需要升级厂商 PON/交换机驱动，必须重新取得匹配 4.19.136 内核的 `.ko`，不能用 ImmortalWrt 生成的同名模块替换。
