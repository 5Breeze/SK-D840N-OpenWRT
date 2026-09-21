include $(TOPDIR)/rules.mk

PKG_NAME:=firewall
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://git.openwrt.org/project/firewall3.git
PKG_SOURCE_DATE:=2025-10-03
PKG_SOURCE_VERSION:=3a65fde5a3e675fdf2a24cb3f5d12d0a426be36e
PKG_MIRROR_HASH:=1cc9756d9a35353c9437355a622b6a4bd53e2d2db4596f1001fe3d90c5983e68

PKG_MAINTAINER:=OpenWrt Developers
PKG_LICENSE:=ISC
PKG_BUILD_FLAGS:=gc-sections lto
PKG_CONFIG_DEPENDS:=CONFIG_IPV6

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/firewall
  SECTION:=net
  CATEGORY:=Base system
  TITLE:=OpenWrt C Firewall (firewall3)
  DEPENDS:=+libubox +libubus +libuci +libip4tc +IPV6:libip6tc +libiptext +IPV6:libiptext6 +libxtables
  PROVIDES:=uci-firewall
  CONFLICTS:=firewall4
endef

define Package/firewall/description
 This package provides the legacy iptables-based UCI firewall implementation.
 It is used here because the device runs a vendor 4.19 kernel and cannot load
 the 6.6 kernel nftables modules shipped by the generic OpenWrt rootfs.
endef

define Package/firewall/conffiles
/etc/config/firewall
/etc/firewall.user
endef

CMAKE_OPTIONS += $(if $(CONFIG_IPV6),,-DDISABLE_IPV6=1)

define Package/firewall/install
	$(INSTALL_DIR) $(1)/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/firewall3 $(1)/sbin/fw3
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/firewall.init $(1)/etc/init.d/firewall
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_DATA) ./files/firewall.hotplug $(1)/etc/hotplug.d/iface/20-firewall
	$(INSTALL_DATA) ./files/firewall.user $(1)/etc/firewall.user
	$(INSTALL_DIR) $(1)/usr/share/fw3
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/helpers.conf $(1)/usr/share/fw3/helpers.conf
endef

$(eval $(call BuildPackage,firewall))
