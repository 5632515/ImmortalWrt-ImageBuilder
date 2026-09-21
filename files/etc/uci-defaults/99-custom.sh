#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE
# 设置默认防火墙规则，方便单网口虚拟机首次访问 WebUI 
# 因为本项目中 单网口模式是dhcp模式 直接就能上网并且访问web界面 避免新手每次都要修改/etc/config/network中的静态ip
# 当你刷机运行后 都调整好了 你完全可以在web页面自行关闭 wan口防火墙的入站数据
# 具体操作方法：网络——防火墙 在wan的入站数据 下拉选项里选择 拒绝 保存并应用即可。
# 注意: 这里原本写死为 @zone[1](默认即 wan 区域)。旁路由模式下 wan 会被删除,
# 下方旁路由分支会按区域名重新精确设置 lan 区域, 不依赖此处的下标。
uci -q set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查配置文件pppoe-settings是否存在 该文件由build.sh动态生成
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >>$LOGFILE
else
    # 读取pppoe信息($enable_pppoe、$pppoe_account、$pppoe_password)
    . "$SETTINGS_FILE"
fi

# 1. 先获取所有物理接口列表
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')

count=$(echo "$ifnames" | wc -w)
echo "Detected physical interfaces: $ifnames" >>$LOGFILE
echo "Interface count: $count" >>$LOGFILE

# 2. 根据板子型号映射WAN和LAN接口
board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
echo "Board detected: $board_name" >>$LOGFILE

wan_ifname=""
lan_ifnames=""
# 此处特殊处理个别开发板网口顺序问题
case "$board_name" in
    "radxa,e20c"|"friendlyarm,nanopi-r5c")
        wan_ifname="eth1"
        lan_ifnames="eth0"
        echo "Using $board_name mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"
        ;;
    *)
        # 默认第一个接口为WAN，其余为LAN
        wan_ifname=$(echo "$ifnames" | awk '{print $1}')
        lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
        echo "Using default mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"
        ;;
esac

# 3. 配置网络
if [ "$count" -eq 1 ]; then
    # 单网口设备，DHCP模式
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway
    uci delete network.lan.dns
    uci commit network
elif [ "$count" -gt 1 ]; then
    # 多网口设备配置
    # 配置WAN
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"
    uci set network.wan.proto='dhcp'

    # 配置WAN6
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"
    uci set network.wan6.proto='dhcpv6'

    # 查找 br-lan 设备 section
    # 注意: busybox awk 不支持 GNU 的 \d, 必须用 POSIX 的 [0-9]
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[[0-9]+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "error：cannot find device 'br-lan'." >>$LOGFILE
    else
        # 删除原有ports
        uci -q delete "network.$section.ports"
        # 添加LAN接口端口
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "Updated br-lan ports: $lan_ifnames" >>$LOGFILE
    fi

    # LAN口设置静态IP
    uci set network.lan.proto='static'
    # 多网口设备 支持修改为别的管理后台地址 在Github Action 的UI上自行输入即可 
    uci set network.lan.netmask='255.255.255.0'
    # 设置路由器管理后台地址
    IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
    if [ -f "$IP_VALUE_FILE" ]; then
        CUSTOM_IP=$(cat "$IP_VALUE_FILE")
        # 用户在UI上设置的路由器后台管理地址
        uci set network.lan.ipaddr=$CUSTOM_IP
        echo "custom router ip is $CUSTOM_IP" >> $LOGFILE
    else
        uci set network.lan.ipaddr='192.168.100.1'
        echo "default router ip is 192.168.100.1" >> $LOGFILE
    fi

    # PPPoE设置
    echo "enable_pppoe value: $enable_pppoe" >>$LOGFILE
    if [ "$enable_pppoe" = "yes" ]; then
        echo "PPPoE enabled, configuring..." >>$LOGFILE
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$pppoe_account"
        uci set network.wan.password="$pppoe_password"
        uci set network.wan.peerdns='1'
        uci set network.wan.auto='1'
        uci set network.wan6.proto='none'
        echo "PPPoE config done." >>$LOGFILE
    else
        echo "PPPoE not enabled." >>$LOGFILE
    fi

    uci commit network
fi

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by wukongdaily"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

# 若luci-app-advancedplus (进阶设置)已安装 则去除zsh的调用 防止命令行报 /usb/bin/zsh: not found的提示
if [ -f /usr/lib/lua/luci/controller/advancedplus.lua ]; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus
    echo "fix ttyd show msg: /usb/bin/zsh: not found" >>$LOGFILE
fi

# 只有安装了 luci-app-quickfile 才执行
if [ -f /usr/bin/quickfile ]; then
    uci set nginx.global.uci_enable='true'
    uci del nginx._lan 2>/dev/null
    uci del nginx._redirect2ssl 2>/dev/null

    uci add nginx server
    uci rename nginx.@server[-1]='_lan'

    uci set nginx._lan.server_name='_lan'
    uci add_list nginx._lan.listen='80 default_server'
    uci add_list nginx._lan.listen='[::]:80 default_server'
    uci add_list nginx._lan.include='conf.d/*.locations'
    uci set nginx._lan.access_log='off; # logd openwrt'

    uci commit nginx
    echo "fix quickfile nginx config" >>$LOGFILE
fi

# 若安装了dockerd 则设置docker的防火墙规则
# 扩大docker涵盖的子网范围 '172.16.0.0/12'
# 方便各类docker容器的端口顺利通过防火墙 
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    FW_FILE="/etc/config/firewall"

    # 删除所有名为 docker 的 zone
    uci delete firewall.docker

    # 先获取所有 forwarding 索引，倒序排列删除
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        echo "Checking forwarding index $idx: src=$src dest=$dest"
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            echo "Deleting forwarding @forwarding[$idx]"
            uci delete firewall.@forwarding[$idx]
        fi
    done
    # 提交删除
    uci commit firewall

# 追加新的 zone + forwarding 配置
cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

else
    echo "未检测到 Docker，跳过防火墙配置。"
fi


# ---- NanoPi R4S PWM fan control (pwmchip1) ----
if grep -qi "NanoPi R4S" /proc/device-tree/model 2>/dev/null && [ -x /etc/init.d/fanctl ]; then
    /etc/init.d/fanctl enable
    echo "fanctl enabled for NanoPi R4S" >>$LOGFILE
fi

# ---- 旁路由(单臂)模式 ----
# 若存在 /etc/config/bypass-settings 且 enable_bypass=yes,
# 则将上方生成的主路由配置(WAN+LAN)改写为单臂旁路由配置。
BYPASS_FILE="/etc/config/bypass-settings"
if [ -f "$BYPASS_FILE" ]; then
    . "$BYPASS_FILE"
fi

if [ "$enable_bypass" = "yes" ]; then
    echo "Configuring bypass (single-arm) mode..." >>$LOGFILE

    # 旁路由不需要 WAN/WAN6, 避免与主路由抢 DHCP
    uci -q delete network.wan
    uci -q delete network.wan6

    # 【关键】把原 WAN 网口并入 br-lan
    # 删除 network.wan 只是移除逻辑接口, 物理网口(如 eth0)会变成
    # 既不属于任何网桥、也没有任何接口引用的游离状态, 内核不会将其 up,
    # 表现就是插网线后客户端拿不到地址(169.254.x.x 自分配地址)。
    # 单臂旁路由应让两个物理口都成为同一二层网桥的成员, 插哪个口都能用。
    # 注意: busybox awk 不支持 GNU 的 \d, 必须用 POSIX 的 [0-9]
    br_section=$(uci show network | awk -F '[.=]' '/\.@?device\[[0-9]+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -n "$br_section" ]; then
        # 重建 ports 列表: 所有物理网口全部加入网桥
        uci -q delete "network.$br_section.ports"
        for port in $ifnames; do
            uci add_list "network.$br_section.ports"="$port"
        done
        echo "Bypass: br-lan ports = $ifnames" >>$LOGFILE

        # 网桥成员全部拔掉时也保持网桥存在, 避免管理地址随之消失
        uci set "network.$br_section.bridge_empty"='1'
        # 单臂模式下缩短 STP 转发延迟, 避免开机前几秒丢包
        uci set "network.$br_section.forward_delay"='2'
    else
        echo "Bypass WARN: br-lan section not found, ports unchanged" >>$LOGFILE
    fi

    # LAN 静态地址 + 指向主路由网关
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr="${bypass_ip:-192.168.110.248}"
    uci set network.lan.netmask="${bypass_netmask:-255.255.255.0}"
    uci set network.lan.gateway="${bypass_gateway:-192.168.110.1}"
    uci set network.lan.dns="${bypass_dns:-223.5.5.5}"
    uci set network.lan.delegate='0'

    # 关闭 DHCP 服务, 地址分配仍由主路由负责
    uci set dhcp.lan.ignore='1'
    uci -q delete dhcp.lan.ra
    uci -q delete dhcp.lan.dhcpv6

    # 【关键】防火墙 lan 区域必须放行入站, 否则删掉 wan 后
    # 上方第 15 行的 firewall.@zone[1].input=ACCEPT 会落在不存在的区域上,
    # 导致 LuCI 与 SSH 无法访问。这里按名字精确定位 lan 区域。
    lan_zone=$(uci show firewall | awk -F '[.=]' '/\.@?zone\[[0-9]+\]\.name=.lan.$/ {print $2; exit}')
    if [ -n "$lan_zone" ]; then
        uci set "firewall.$lan_zone.input"='ACCEPT'
        uci set "firewall.$lan_zone.forward"='ACCEPT'
        uci set "firewall.$lan_zone.masq"='0'
        echo "Bypass: firewall lan zone = $lan_zone (input ACCEPT)" >>$LOGFILE
    fi
    # 移除指向已删除 wan 区域的转发规则
    for idx in $(uci show firewall | grep '=forwarding' | cut -d'[' -f2 | cut -d']' -f1 | sort -rn); do
        fsrc=$(uci -q get firewall.@forwarding[$idx].src)
        fdest=$(uci -q get firewall.@forwarding[$idx].dest)
        if [ "$fsrc" = "wan" ] || [ "$fdest" = "wan" ]; then
            uci -q delete firewall.@forwarding[$idx]
        fi
    done
    # 删除 wan 区域本体
    wan_zone=$(uci show firewall | awk -F '[.=]' '/\.@?zone\[[0-9]+\]\.name=.wan.$/ {print $2; exit}')
    [ -n "$wan_zone" ] && uci -q delete "firewall.$wan_zone"

    uci commit network
    uci commit dhcp
    uci commit firewall
    echo "Bypass mode done: ${bypass_ip:-192.168.110.248} gw ${bypass_gateway:-192.168.110.1}" >>$LOGFILE

    # 【救援】写入一键回退脚本。
    # 若旁路由参数与实际网段不符导致失联,
    # 可用 USB 转串口或 TF 卡挂载执行它恢复为 DHCP 自动取地址。
    cat > /usr/sbin/bypass-rescue.sh <<'RESCUE'
#!/bin/sh
# 旁路由救援: 恢复 LAN 为 DHCP 客户端, 重新启用 DHCP 服务器
# 用法: sh /usr/sbin/bypass-rescue.sh  然后重启或 /etc/init.d/network restart
uci set network.lan.proto='dhcp'
uci -q delete network.lan.ipaddr
uci -q delete network.lan.netmask
uci -q delete network.lan.gateway
uci -q delete network.lan.dns
uci -q delete dhcp.lan.ignore
uci commit network
uci commit dhcp
echo "已恢复为 DHCP 模式, 重启网络中..."
/etc/init.d/network restart
RESCUE
    chmod +x /usr/sbin/bypass-rescue.sh
    echo "Rescue script written to /usr/sbin/bypass-rescue.sh" >>$LOGFILE
fi

exit 0
