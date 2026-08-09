# netifd

## Changed
```
$ diff system-linux.orig system-linux.c
1554c1554,1555
<       nla_put_u8(msg, IFLA_BR_VLAN_FILTERING, !!cfg->vlan_filtering);
---
>       if (cfg->vlan_filtering)
>               nla_put_u8(msg, IFLA_BR_VLAN_FILTERING, !!cfg->vlan_filtering);
```

## Output
```
> openwrt/build_dir/target-aarch64_generic_musl/netifd-2025.05.23~7901e66c$ ll ipkg-aarch64_generic/netifd/sbin/netifd
-rwxr-xr-x 1 huxiang huxiang 266019  8月  9 22:42 ipkg-aarch64_generic/netifd/sbin/netifd
> openwrt/build_dir/target-aarch64_generic_musl/netifd-2025.05.23~7901e66c$ ll netifd
-rwxr-xr-x 1 huxiang huxiang 1569712  8月  9 22:42 netifd
```

