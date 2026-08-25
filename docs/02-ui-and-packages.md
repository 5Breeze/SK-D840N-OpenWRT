# LuCI 现代 UI 与插件教程

## 当前默认配置

`immortalwrt.config` 已包含：

```text
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl-openssl=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
CONFIG_PACKAGE_luci-app-ddns=y
CONFIG_PACKAGE_luci-app-https-dns-proxy=y
CONFIG_PACKAGE_luci-app-ttyd=y
```

`overlay/etc/uci-defaults/99-skd840n-luci` 会在首次启动时把 Argon 和简体中文设为默认。以后在 LuCI 的“系统 → 系统 → 语言和界面”中仍可切换主题。

## 添加普通插件

直接编辑仓库根目录的 `immortalwrt.config`，每行使用：

```text
CONFIG_PACKAGE_包名=y
```

比较适合先尝试的包：

```text
# 实时流量和历史统计
CONFIG_PACKAGE_luci-app-statistics=y

# UPnP
CONFIG_PACKAGE_luci-app-upnp=y

# 广告过滤；依赖 DNS 和防火墙能力，刷机后需实际验证
CONFIG_PACKAGE_luci-app-adblock-fast=y

# 多 WAN 管理；需要验证厂商内核的策略路由能力
CONFIG_PACKAGE_luci-app-mwan3=y
```

修改后重新运行 `build-immortalwrt-rootfs.sh`。脚本会执行 `make defconfig`，依赖包将自动加入完整 `.config`。

## 使用 menuconfig 选择

如果更习惯菜单：

```sh
cd ~/sk-d840n-build/immortalwrt
make menuconfig
```

LuCI 主题位于：

```text
LuCI → Themes
```

LuCI 插件位于：

```text
LuCI → Applications
```

选择完成后，把差异保存回工具包配置，否则下次运行脚本会用 `immortalwrt.config` 覆盖它：

```sh
./scripts/diffconfig.sh > /你的/SK-D840N-OpenWRT/immortalwrt.config
```

## 添加自己的文件

将文件按最终 rootfs 的绝对路径放进 `overlay/`。例如：

```text
overlay/etc/config/myservice
overlay/etc/init.d/myservice
overlay/usr/bin/myscript
```

构建脚本会把 `overlay/` 合并到生成的 rootfs。可执行脚本需在 Linux 中设置权限：

```sh
chmod 755 overlay/etc/init.d/myservice overlay/usr/bin/myscript
```

## 不建议直接加入的插件

以下插件常依赖 TUN、veth、复杂 nftables/iptables、透明代理、容器或其他特定内核模块：

```text
luci-app-openclash
luci-app-passwall
luci-app-homeproxy
luci-app-sqm
luci-app-dockerman
```

这台设备运行厂商 `4.19.136` 内核，而 ImmortalWrt `openwrt-24.10` 的 `kmod-*` 针对 6.6 内核，二者不能混用。可以先在设备上检查厂商内核能力：

```sh
zcat /proc/config.gz 2>/dev/null | grep -E 'TUN|VETH|NETFILTER|NFT|IFB|SCHED'
lsmod
```

只有确认所需功能已经内建或存在匹配 `4.19.136` 的厂商模块后，才应加入相关插件。LuCI 页面能够打开并不代表底层代理、QoS 或容器功能可用。

## 刷机后安装软件包

优先选择重新编译进 rootfs。运行时 `opkg install` 只能使用与同一 ImmortalWrt 分支、同一 `aarch64_generic` 用户空间匹配的软件包，并且应避开所有 `kmod-*` 依赖。出现下面这类错误时不要强制安装：

```text
cannot satisfy dependency kernel (= 6.6...)
```

使用 `--force-depends` 只会绕过检查，不能让 6.6 内核模块在 4.19 内核上运行。

