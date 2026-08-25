# 编译教程

## 方案说明

SK-D840N 当前仓库不是完整的 OpenWrt target，而是厂商 4.19 内核、DTB、驱动和一个 OpenWrt ARM64 rootfs 的组合。因此本工具包编译 ImmortalWrt 用户空间，然后合并原仓库的硬件相关文件，最终只生成可刷写的 `rootfs.jffs2`。

不要刷 ImmortalWrt `armsr/armv8` 生成的通用 kernel、DTB、combined、factory 或 sysupgrade 镜像。它们的 6.6 内核不包含 SK-D840N 的 `zxic,zx-*`、PON 和交换机驱动。

## 方法一：GitHub Actions 一键编译

1. 在 GitHub 上 fork `huxiangjs/SK-D840N-OpenWRT`。
2. 将本工具包中的以下文件和目录上传到 fork 的仓库根目录：

   ```text
   .github/workflows/build-immortalwrt.yml
   build-immortalwrt-rootfs.sh
   immortalwrt.config
   overlay/
   ```

3. 打开仓库的 **Actions** 页面。
4. 选择 **Build SK-D840N ImmortalWrt rootfs**。
5. 点击 **Run workflow**。
6. 等待构建结束，进入该次运行页面，在 **Artifacts** 下载 `SK-D840N-ImmortalWrt-rootfs.zip`。
7. 解压后确认包含：

   ```text
   rootfs.jffs2
   boot.bin
   uImage
   board.dtb
   immortalwrt.full.config
   BUILD-INFO.txt
   SHA256SUMS
   ```

GitHub Actions 免费 runner 有执行时间和磁盘限制。如果编译因空间不足失败，请改用本地 Linux；不要通过删除源码中的 target 或内核文件来“精简”，否则 staged rootfs 可能不完整。

## 方法二：本地 Linux 编译

建议使用 Debian 11/12 或 Ubuntu 22.04/24.04 x86_64，至少 4 GB 内存、25 GB 可用空间。源码必须放在大小写敏感的 Linux 文件系统内，不能放在 Windows NTFS 挂载目录中编译。

安装依赖：

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

以普通用户执行编译，不要使用 root 或 `sudo make`：

```sh
mkdir -p ~/sk-d840n-build
cd ~/sk-d840n-build
git clone https://github.com/你的用户名/SK-D840N-OpenWRT.git
cd SK-D840N-OpenWRT
chmod +x build-immortalwrt-rootfs.sh
SK_SOURCE="$PWD" \
IMMORTAL_DIR="$HOME/sk-d840n-build/immortalwrt" \
DIST_DIR="$PWD/dist" \
JOBS="$(nproc)" \
./build-immortalwrt-rootfs.sh
```

第一次编译会下载和编译完整工具链，时间可能较长。失败时使用单线程详细日志定位：

```sh
cd ~/sk-d840n-build/immortalwrt
make -j1 V=s
```

修复错误后重新运行构建脚本即可；`dl/` 和已完成的编译缓存会被复用。

## 校验生成物

```sh
cd dist
sha256sum -c SHA256SUMS
ls -lh rootfs.jffs2 boot.bin uImage board.dtb
cat BUILD-INFO.txt
```

`rootfs.jffs2` 必须小于 `0x0f100000` 字节；构建脚本会自动检查。`boot.bin`、`uImage` 和 `board.dtb` 只是从原仓库复制，没有被 ImmortalWrt 替换。
