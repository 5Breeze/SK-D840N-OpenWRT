# SK-D840N-OpenWRT

**SK-D840N OpenWRT rootfs**

**Feature:**

* AArch64 @ Cortex A53x2 1000MHZ
* DDR3 512MiB
* Nand Flash 256MBytes

![PCB](images/PCB.JPG)

## Information

### Verified hardware version

|   V2024 |  V2025  |
| :-----: | :-----: |
| ![VERSION_2024](images/VERSION_2024.JPG) | ![VERSION_2025](images/VERSION_2025.JPG) |

### List of components

|         |  TYPE1  | TYPE2 |
| :-----: | :-----: | :-----: |
| SoC | ![SoC](images/SoC.png) |    |
| DDR | ![DDR_TYPE1](images/DDR_TYPE1.JPG) | ![DDR_TYPE1](images/DDR_TYPE2.JPG) |
| ETH PHY | ![PHY_2.5G](images/PHY_2.5G.JPG) |    |
| FLASH | ![NAND_FLASH](images/NAND_FLASH.JPG) |    |

### Network support

|          | **eth0** | **eth1** | **eth2** | **eth3** | **wan** | **lan** |
| :------: | :------: | :------: | :------: | :------: | :-----: | :-----: |
| **eth0** |   —      |   ❌     |    ❌    |    ❌    |   ✅    |   ❌    |
| **eth1** |  ❌      |   —      |    ❌    |    ❌    |    ❌   |   ✅    |
| **eth2** |  ❌      |   ❌     |    —     |    ❌    |    ❌   |   ✅    |
| **eth3** |  ❌      |   ❌     |    ❌    |    —     |    ❌   |   ✅    |
| **wan**  |  ✅      |   ❌     |    ❌    |    ❌    |    —    |   ❌    |
| **lan**  |  ❌      |   ✅     |    ✅    |    ✅    |    ❌   |   —     |

### USB support

|       | **name** | **status** | 
| :---: | :------: | :--------: |
| **1** | USB 2.0  |    ✅      |
| **2** | USB 3.0  |    ✅      |

### rootfs template

* from: [generic-ext4-rootfs.img.gz](https://downloads.openwrt.org/releases/24.10.8/targets/armsr/armv8/openwrt-24.10.8-armsr-armv8-generic-ext4-rootfs.img.gz)
* release page: [releases](https://downloads.openwrt.org/releases/24.10.8/targets/armsr/armv8/)
* gcc: [gcc-13.3.0-musl.Linux-x86-64.tar.zst](https://downloads.openwrt.org/releases/24.10.8/targets/armsr/armv8/openwrt-toolchain-24.10.8-armsr-armv8_gcc-13.3.0_musl.Linux-x86_64.tar.zst)

## Quick Start

### Firmware download

[Firmware Release](https://github.com/huxiangjs/SK-D840N-OpenWRT/releases)

### Preparing the Environment

1. Connect the SK-D840N to your computer using an Ethernet cable.
2. Configure the computer's static IP address as: `192.168.1.40`
3. Start the TFTP service to transfer the firmware (Python 3.10.12):
   ```
   python -m pip install -r requirements.txt
   python tftp.py
   ```
4. Connect the serial port to the computer at a baud rate of 115200.

![Link](images/Serial_Port.png)

### Firmware flashing

1. After powering on the SK-D840N, enter "u" in the serial port, and it will remain in U-Boot.
2. Flash the Bootloader (⚠️ **Do not disconnect the power during the flashing process!** )
   ```
   tftpboot 0x88000000 192.168.1.40:boot.bin
   nand erase 0x00000000 0x00200000
   nand write 0x88000000 0x00000000 ${filesize}
   ```
3. Flash the Kernel
   ```
   tftpboot 0x88000000 192.168.1.40:uImage
   nand erase 0x00200000 0x00800000
   nand write 0x88000000 0x00200000 ${filesize}
   ```
4. Flash the dtb
   ```
   tftpboot 0x88000000 192.168.1.40:board.dtb
   nand erase 0x00a00000 0x00100000
   nand write 0x88000000 0x00a00000 ${filesize}
   ```
5. Move the param partition
   ```
   nand read 0x88000000 0x04800000 0x00400000
   nand erase 0x00b00000 0x00400000
   nand write 0x88000000 0x00b00000 0x00400000
   ```
6. Flash the rootfs (💡 If you need to reset it in the future, simply reflash this partition. )
   ```
   tftpboot 0x88000000 192.168.1.40:rootfs.jffs2
   nand erase 0x00f00000 0x0f100000
   nand write 0x88000000 0x00f00000 ${filesize}
   ```
7. Reboot
   ```
   reset
   ```
8. At this point, you can log in to OpenWRT using a web browser or SSH.

|     port    | **name** |    **web browser**  |       **SSH**        | 
| :---------: | :------: | :-----------------: | :------------------: |
| **1-2.5G**  |   eth0   |          @DHCP      |       @DHCP          |
| **2-1000M** |   eth1   |  http://192.168.1.1 | ssh root@192.168.1.1 |
| **3-1000M** |   eth2   |  http://192.168.1.1 | ssh root@192.168.1.1 |
| **4-1000M** |   eth3   |  http://192.168.1.1 | ssh root@192.168.1.1 |

## Manual Packaging

### System Environment
```shell
# Ubuntu 22.04
> cat /proc/version
Linux version 6.5.0-35-generic (buildd@lcy02-amd64-079) (x86_64-linux-gnu-gcc-12 (Ubuntu 12.3.0-1ubuntu1~22.04) 12.3.0, GNU ld (GNU Binutils for Ubuntu) 2.38) #35~22.04.1-Ubuntu SMP PREEMPT_DYNAMIC Tue May  7 09:00:52 UTC 2
```

### Get the repository && Init
```shell
sudo su
git clone https://github.com/huxiangjs/SK-D840N-OpenWRT.git
cd SK-D840N-OpenWRT
./scripts/gitkeep.sh install
```

### Packaging ramdisk.cpio.lzma
```shell
./scripts/pack_to_ramdisk.sh
```

### Packaging ramdisk.cpio.lzma
```shell
./scripts/pack_to_jffs2.sh
```
