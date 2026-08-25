# 刷机、升级和恢复教程

## 必需设备

- 3.3 V USB 转 TTL 串口线；禁止把 5 V 接入路由器；
- 网线；
- TFTP 服务器；
- 已校验的 `rootfs.jffs2`；
- 原仓库的 `boot.bin`、`uImage`、`board.dtb` 以及设备原始备份。

串口参数为 `115200 8N1`。电脑有线网卡设置静态地址：

```text
IP:      192.168.1.40
Mask:    255.255.255.0
Gateway: 留空
```

关闭其他会抢路由的网卡或 VPN，并确保防火墙允许 TFTP UDP 69 端口。把待刷文件放进 TFTP 根目录。

## 刷写前必须检查

1. 校验下载的文件：

   ```sh
   sha256sum -c SHA256SUMS
   ```

2. 从当前系统保存以下信息：

   ```sh
   cat /proc/mtd
   cat /proc/cmdline
   fw_printenv 2>/dev/null
   ```

3. 备份原始 flash。不同固件中的 MTD 编号可能不同，必须依据 `/proc/mtd` 的分区名称操作，不要照抄其他设备的 `/dev/mtdX` 编号。
4. 保留设备标签、MAC 地址和 `param` 分区备份。`param` 包含设备相关数据，不能使用他人的文件替换。

## 情况 A：已经运行 SK-D840N-OpenWRT，仅升级 rootfs

这是风险最低的方式，不需要重刷 bootloader、kernel、DTB，也不要再次移动 `param` 分区。

1. 启动 TFTP 服务，确认 TFTP 根目录中存在 `rootfs.jffs2`。
2. 串口连接设备并上电，在启动提示中输入 `u` 停留在 U-Boot。
3. 下载 rootfs 到 RAM：

   ```text
   tftpboot 0x88000000 192.168.1.40:rootfs.jffs2
   ```

4. 记录 U-Boot 显示的文件大小，并确认小于 `0x0f100000`。
5. 擦除并写入 rootfs 分区：

   ```text
   nand erase 0x00f00000 0x0f100000
   nand write 0x88000000 0x00f00000 ${filesize}
   ```

6. 重启：

   ```text
   reset
   ```

擦除之后、写入完成之前不能断电。地址仅适用于你提供的 SK-D840N 项目布局；如果串口或 `/proc/mtd` 显示不同布局，应立即停止。

## 情况 B：厂商原始系统首次转换

首次转换需要同时刷 bootloader、kernel、DTB，并移动设备自身的 `param`。这是高风险操作，必须保持串口连接和稳定供电。

停在 U-Boot 后按顺序执行：

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

`param` 移动只能读取并写回本机内容，绝不能把发布包或另一台设备的 `param` 写入。如果设备已经完成过 SK-D840N-OpenWRT 转换，不要重复执行该移动步骤。

## 首次启动验证

保持串口连接。第一次启动生成 JFFS2 状态和 UCI 配置可能比平时慢，不要立即断电。登录后检查：

```sh
uname -r
cat /etc/openwrt_release
cat /tmp/sysinfo/board_name
ip -br link
ip -br addr
logread | grep -E 'kmod|netdriver|np_133|gpon|switch|error|fail'
df -h
```

预期结果：

- `uname -r` 仍为厂商 `4.19.136` 系列；
- 系统发行信息为 ImmortalWrt；
- board name 为 `zte,133`；
- `eth0` 为 WAN，`eth1 eth2 eth3` 加入 LAN；
- `http://192.168.1.1` 或 `https://192.168.1.1` 能打开 Argon LuCI。

## rootfs 启动失败时恢复

只要 U-Boot、kernel 和 DTB 没有损坏，重新停在 U-Boot，使用同一地址刷回上一次能够启动的 `rootfs.jffs2` 即可：

```text
tftpboot 0x88000000 192.168.1.40:rootfs-backup.jffs2
nand erase 0x00f00000 0x0f100000
nand write 0x88000000 0x00f00000 ${filesize}
reset
```

如果没有串口输出，或 U-Boot 已损坏，不要继续猜测 NAND 地址；此时可能需要编程器和完整 NAND 备份恢复。

