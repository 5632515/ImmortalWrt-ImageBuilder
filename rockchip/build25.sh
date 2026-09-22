#!/bin/bash
# Log file for debugging
source shell/apk-custom-packages.sh
echo "第三方APK软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
# yml 传入的路由器型号 PROFILE
echo "Building for profile: $PROFILE"
# yml 传入的固件大小 ROOTFS_PARTSIZE
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"

echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入环境变量ENABLE_PPPOE等 写入配置文件 供99-custom.sh读取
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  # ============= 同步第三方插件库==============
  # 同步第三方软件仓库run/apk
  echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
  git clone --depth=1 https://github.com/wukongdaily/apk.git /tmp/store-apk-repo

  # 拷贝 run/arm64 下所有 run 文件和apk文件 到 extra-packages 目录
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-apk-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

  echo "✅ Run files copied to extra-packages:"
  # 解压并拷贝apk到packages目录
  sh shell/apk-prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."
echo "查看repositories信息——————"
cat repositories
# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi
# 文件管理器
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"

# ==========================================================
# NanoPi R4S (RK3399 / aarch64_generic) 常用驱动与依赖组件
# 所有包名均已在 immortalwrt 25.12.x aarch64_generic 源中核实存在
# ==========================================================

# ---- 代理内核与透明代理内核模块 (PassWall 必需) ----
PACKAGES="$PACKAGES xray-core"
PACKAGES="$PACKAGES sing-box"
PACKAGES="$PACKAGES hysteria"
PACKAGES="$PACKAGES geoview"
PACKAGES="$PACKAGES chinadns-ng"
PACKAGES="$PACKAGES dns2socks"
PACKAGES="$PACKAGES ipt2socks"
PACKAGES="$PACKAGES microsocks"
PACKAGES="$PACKAGES tcping"
PACKAGES="$PACKAGES haproxy"
PACKAGES="$PACKAGES v2ray-geoip v2ray-geosite"
# nftables 透明代理模块 (25.12 默认 fw4/nftables)
PACKAGES="$PACKAGES kmod-nft-socket kmod-nft-tproxy kmod-nft-nat"
# iptables 兼容层, 供 PassWall 回落到 iptables 模式使用
PACKAGES="$PACKAGES iptables-nft iptables-mod-socket iptables-mod-tproxy"
PACKAGES="$PACKAGES kmod-tun"
PACKAGES="$PACKAGES kmod-inet-diag"

# ---- 网络性能与拥塞控制 ----
PACKAGES="$PACKAGES kmod-tcp-bbr"

# ---- RK3399 板载与外设驱动 ----
# R4S 原生千兆网卡 (RTL8211 PHY + PCIe r8169)
PACKAGES="$PACKAGES kmod-r8169"
# USB 3.0 外接网卡常用驱动
PACKAGES="$PACKAGES kmod-usb-net kmod-usb-net-rtl8152 kmod-usb-net-asix-ax88179"
# USB 存储与常用文件系统
PACKAGES="$PACKAGES kmod-usb-storage kmod-usb-storage-uas"
PACKAGES="$PACKAGES kmod-fs-ext4 kmod-fs-vfat kmod-fs-exfat kmod-fs-ntfs3"
PACKAGES="$PACKAGES kmod-nls-utf8 kmod-nls-cp437 kmod-nls-iso8859-1"
# 注: RK3399 的 PWM 控制器与硬件加密引擎均为内核内建(built-in),
# 无独立 kmod 包, /sys/class/pwm/pwmchip1 开机即存在, 无需额外安装。
# 板载温度传感器(thermal_zone0)同为内建。

# ---- 基础网络工具与证书 ----
PACKAGES="$PACKAGES ca-certificates ca-bundle"
PACKAGES="$PACKAGES wget-ssl"
PACKAGES="$PACKAGES ip-full"
PACKAGES="$PACKAGES bind-dig"
PACKAGES="$PACKAGES nftables-json"
PACKAGES="$PACKAGES ethtool"
PACKAGES="$PACKAGES pciutils usbutils"
PACKAGES="$PACKAGES htop"
PACKAGES="$PACKAGES bash"
PACKAGES="$PACKAGES unzip"
PACKAGES="$PACKAGES luci-compat"

# ---- 旁路由常用 LuCI 组件 ----
PACKAGES="$PACKAGES luci-i18n-upnp-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"

# ---- 文件共享与内网穿透 (官方源已核实存在) ----
# Samba4 网络共享; luci-i18n-samba4-zh-cn 会自动带入 luci-app-samba4 与 samba4-server
PACKAGES="$PACKAGES luci-i18n-samba4-zh-cn"
# ZeroTier 虚拟组网; 同理会自动带入 luci-app-zerotier 与 zerotier 本体
PACKAGES="$PACKAGES luci-i18n-zerotier-zh-cn"

# ======== shell/apk-custom-packages.sh =======
# 合并imm仓库以外的第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
    # Download latest openclash Client
    URL=$(curl -s https://api.github.com/repos/vernesong/OpenClash/releases/latest \
      | grep "browser_download_url.*apk" \
      | head -n1 \
      | cut -d '"' -f 4)
    echo "OpenClash latest apk: $URL"
    wget "$URL" -P /home/build/immortalwrt/packages/
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

if echo "$PACKAGES" | grep -q "luci-app-ssr-plus"; then
    echo "✅ 已选择 luci-app-ssr-plus，添加 mihomo core"
    mkdir -p files/usr/bin
    # Download mihomo
    MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.24/mihomo-linux-arm64-v1.19.24.gz"
    mkdir -p files/usr/bin
    wget -qO- "$MIHOMO_URL" | gzip -dc > files/usr/bin/mihomo
    chmod +x files/usr/bin/mihomo
    echo "✅ 已下载 mihomo core"
    ls -lah files/usr/bin
else
    echo "⚪️ 未选择 luci-app-ssr-plus"
fi


make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
