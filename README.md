# SK-D840N-OpenWRT

**SK-D840N OpenWRT rootfs**

![PCB](images/PCB.JPG)

## Information

### Verified hardware version

|   V2024 |  V2025  |
| :-----: | :-----: |
| ![VERSION_2024](images/VERSION_2024.JPG) | ![VERSION_2025](images/VERSION_2025.JPG) |

### List of components

|         |  TYPE1  | TYPE2 |
| :-----: | :-----: | :-----: |
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
   pip install -r requirements.txt
   python tftp.py
   ```
4. Connect the serial port to the computer at a baud rate of 115200.


### Firmware flashing

1. Flash the Bootloader
   ```
   tftpboot 0x88000000 192.168.1.40:boot.bin
   nand erase 0x00000000 0x00200000
   nand write 0x88000000 0x00000000 ${filesize}
   ```
2. Flash the Kernel
   ```
   tftpboot 0x88000000 192.168.1.40:uImage
   nand erase 0x00200000 0x00800000
   nand write 0x88000000 0x00200000 ${filesize}
   ```
3. Flash the dtb
   ```
   tftpboot 0x88000000 192.168.1.40:board.dtb
   nand erase 0x00a00000 0x00100000
   nand write 0x88000000 0x00a00000 ${filesize}
   ```
4. Move the param partition
   ```
   nand read 0x88000000 0x04800000 0x00400000
   nand erase 0x00b00000 0x00400000
   nand write 0x88000000 0x00b00000 0x00400000
   ```
5. Flash the rootfs
   ```
   tftpboot 0x88000000 192.168.1.40:rootfs.jffs2
   nand erase 0x00f00000 0x0f100000
   nand write 0x88000000 0x00f00000 ${filesize}
   ```

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


