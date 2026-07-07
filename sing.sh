#!/bin/bash
set -euo pipefail

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

die() {
    echo -e "${RED}错误: $*${NC}" >&2
    exit 1
}

is_container() {
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        local virt
        virt=$(systemd-detect-virt --container || echo "none")
        if [ "$virt" != "none" ]; then
            return 0
        fi
    fi
    if [ -f /.dockerenv ] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
        return 0
    fi
    return 1
}

is_valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

is_port_in_use() {
    local port="$1"
    ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
}

find_next_free_port() {
    local port="$1"
    while [ "$port" -le 65535 ]; do
        if ! is_port_in_use "$port"; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
    done
    return 1
}

get_latest_apt_112_version() {
    apt-cache madison sing-box 2>/dev/null \
        | awk '{print $3}' \
        | grep -E '^1\.12\.[0-9]+([-+~].*)?$' \
        | sort -V \
        | tail -n 1
}

install_sing_box_apt_112() {
    local ver
    ver="$(get_latest_apt_112_version)"
    if [ -n "$ver" ]; then
        $SUDO apt-mark unhold sing-box sing-box-beta >/dev/null 2>&1 || true
        if ! $SUDO apt-get install -yq --allow-downgrades --allow-change-held-packages "sing-box=$ver"; then
            $SUDO apt-mark unhold sing-box sing-box-beta >/dev/null 2>&1 || true
            $SUDO apt-get install -yq --allow-downgrades --allow-change-held-packages "sing-box=$ver"
        fi
    else
        die "apt 源中未找到 sing-box 1.12.x 版本。"
    fi
}

get_latest_github_112_version() {
    local tmp_file
    tmp_file="$(mktemp)"
    if curl -fsSL --connect-timeout 5 --max-time 20 \
        "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=100" \
        -o "$tmp_file"; then
        jq -r '.[].tag_name' "$tmp_file" 2>/dev/null \
            | sed -n 's/^v\(1\.12\.[0-9]\+\)$/\1/p' \
            | sort -V \
            | tail -n 1
    fi
    rm -f "$tmp_file"
}

get_public_ip() {
    local ip=""
    ip="$(curl -4 -fsS --max-time 5 ifconfig.me 2>/dev/null || true)"
    if [ -z "$ip" ]; then
        ip="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
    fi
    if [ -z "$ip" ]; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    echo "$ip"
}

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    SUDO=""
else
    command -v sudo >/dev/null 2>&1 || die "需要 root 权限或 sudo。"
    SUDO="sudo"
fi

SOCKS_LINK6=""
VLESS_LINK6=""

echo -e "${CYAN}正在开始 sing-box 全自动部署...${NC}"

# 协议模式选择
echo -e "\n请选择协议模式:"
echo "1. VLESS + SOCKS5（默认）"
echo "2. 仅 VLESS"
read -p "请输入选项 [默认: 1]: " PROTO_CHOICE
PROTO_CHOICE=${PROTO_CHOICE:-1}
if [ "$PROTO_CHOICE" != "1" ] && [ "$PROTO_CHOICE" != "2" ]; then
    echo -e "${YELLOW}无效选项，已回退到默认模式: 1${NC}"
    PROTO_CHOICE=1
fi

# 端口配置（可自定义，回车使用默认值）
read -p "请输入 VLESS 端口 [默认: 443]: " VLESS_PORT
VLESS_PORT=${VLESS_PORT:-443}
is_valid_port "$VLESS_PORT" || die "VLESS 端口无效: $VLESS_PORT"
ORIG_VLESS_PORT="$VLESS_PORT"
VLESS_PORT="$(find_next_free_port "$VLESS_PORT")" || die "未找到可用的 VLESS 端口。"
if [ "$VLESS_PORT" != "$ORIG_VLESS_PORT" ]; then
    echo -e "${YELLOW}VLESS 端口 ${ORIG_VLESS_PORT} 已被占用，自动调整为 ${VLESS_PORT}${NC}"
fi
if [ "$PROTO_CHOICE" != "2" ]; then
    read -p "请输入 SOCKS5 端口 [默认: 1080]: " SOCKS_PORT
    SOCKS_PORT=${SOCKS_PORT:-1080}
    is_valid_port "$SOCKS_PORT" || die "SOCKS5 端口无效: $SOCKS_PORT"
    ORIG_SOCKS_PORT="$SOCKS_PORT"
    if [ "$SOCKS_PORT" -eq "$VLESS_PORT" ]; then
        SOCKS_PORT=$((SOCKS_PORT + 1))
    fi
    SOCKS_PORT="$(find_next_free_port "$SOCKS_PORT")" || die "未找到可用的 SOCKS5 端口。"
    if [ "$SOCKS_PORT" != "$ORIG_SOCKS_PORT" ]; then
        echo -e "${YELLOW}SOCKS5 端口 ${ORIG_SOCKS_PORT} 已冲突或被占用，自动调整为 ${SOCKS_PORT}${NC}"
    fi
fi

echo -e "\n请选择 sing-box 安装方式:"
echo "1. 从官方 apt 软件源安装 (推荐, 由源决定具体版本)"
echo "2. 从 GitHub 下载最新的 1.12.x Release 离线安装"
read -p "请输入选项 [默认: 1]: " INSTALL_CHOICE
INSTALL_CHOICE=${INSTALL_CHOICE:-1}
if [ "$INSTALL_CHOICE" != "1" ] && [ "$INSTALL_CHOICE" != "2" ]; then
    echo -e "${YELLOW}无效选项，已回退到默认安装方式: 1${NC}"
    INSTALL_CHOICE=1
fi

echo -e "\n是否同时进行服务器网络性能与内核优化? (包括开启BBR、扩大连接数与缓冲区等限制)"
echo "提升高并发跨境稳定性。推荐新服务器选择是 (Y)。"
read -p "请输入选项 [Y/n, 默认: Y]: " OPTIMIZE_CHOICE
OPTIMIZE_CHOICE=${OPTIMIZE_CHOICE:-Y}

# 1. 自动清理冲突版本 (解决 dpkg 报错)
echo -e "\n正在检查并清理旧版本..."
$SUDO systemctl stop sing-box &>/dev/null || true
$SUDO apt-mark unhold sing-box sing-box-beta >/dev/null 2>&1 || true
$SUDO apt-get remove --purge sing-box sing-box-beta -y &>/dev/null || true
$SUDO apt-get autoremove -y &>/dev/null || true

# 2. 安装依赖并配置官方仓库
$SUDO apt-get update -qq
$SUDO apt-get install -y curl jq uuid-runtime openssl
$SUDO mkdir -p /etc/apt/keyrings
$SUDO curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
$SUDO chmod a+r /etc/apt/keyrings/sagernet.asc

echo "Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc" | $SUDO tee /etc/apt/sources.list.d/sagernet.sources > /dev/null

$SUDO apt-get update -qq

if [ "$INSTALL_CHOICE" == "2" ]; then
    echo "正在从 GitHub 获取最新的 sing-box 1.12.x 版本..."
    ARCH=$(dpkg --print-architecture)
    GITHUB_LATEST="$(get_latest_github_112_version || true)"
    if [ -z "$GITHUB_LATEST" ]; then
        echo -e "${RED}无法从 GitHub 获取最新版本，自动回退到 apt 软件源安装...${NC}"
        install_sing_box_apt_112
    else
        DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${GITHUB_LATEST}/sing-box_${GITHUB_LATEST}_linux_${ARCH}.deb"
        FILE_NAME="/tmp/sing-box_${GITHUB_LATEST}_linux_${ARCH}.deb"
        echo "正在下载: ${DOWNLOAD_URL}"
        if curl -L --fail "$DOWNLOAD_URL" -o "$FILE_NAME"; then
            $SUDO dpkg -i "$FILE_NAME" || {
                echo -e "${YELLOW}dpkg 安装失败，自动清理并回退到 apt 软件源安装...${NC}"
                rm -f "$FILE_NAME"
                install_sing_box_apt_112
            }
            rm -f "$FILE_NAME"
        else
            echo -e "${RED}包下载失败，自动回退到 apt 软件源安装...${NC}"
            install_sing_box_apt_112
        fi
    fi
else
    echo "正在从 apt 软件源安装 sing-box 1.12.x 稳定版..."
    install_sing_box_apt_112
fi

# 锁定版本，避免被 apt upgrade 自动升级掉
$SUDO apt-mark hold sing-box 2>/dev/null || true

# 如果以后想解锁升级，运行：
# sudo apt-mark unhold sing-box
# sudo apt-get update && sudo apt-get upgrade sing-box

# 3. 服务器网络与内核优化 (可选)
if [[ "$OPTIMIZE_CHOICE" =~ ^[Yy]$ || "$OPTIMIZE_CHOICE" == "" ]]; then
    echo -e "\n${CYAN}正在应用系统网络与内核优化...${NC}"
    if is_container; then
        echo -e "${YELLOW}检测到处于容器环境 (LXC/Docker)，无法修改宿主机内核网络参数。${NC}"
        echo -e "${YELLOW}已自动跳过内核网络优化参数配置。${NC}"
        $SUDO rm -f /etc/sysctl.d/99-sing-box-optimize.conf
    else
        $SUDO modprobe tcp_bbr 2>/dev/null || true
        MEM_TOTAL_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
        BUF_BYTES=$((MEM_TOTAL_KB * 5 / 100 * 1024))
        [ "$BUF_BYTES" -lt 16777216 ] && BUF_BYTES=16777216
        [ "$BUF_BYTES" -gt 67108864 ] && BUF_BYTES=67108864
        TCP_BUF_MAX=$((BUF_BYTES / 2))
        [ "$TCP_BUF_MAX" -lt 8388608 ] && TCP_BUF_MAX=8388608

        sysctl_params=(
            "net.core.default_qdisc=fq"
            "net.ipv4.tcp_congestion_control=bbr"
            "net.core.somaxconn=4096"
            "net.core.netdev_max_backlog=16384"
            "net.ipv4.tcp_max_syn_backlog=16384"
            "net.core.rmem_max=${BUF_BYTES}"
            "net.core.wmem_max=${BUF_BYTES}"
            "net.ipv4.tcp_rmem=4096 87380 ${TCP_BUF_MAX}"
            "net.ipv4.tcp_wmem=4096 65536 ${TCP_BUF_MAX}"
            "net.ipv4.udp_rmem_min=16384"
            "net.ipv4.udp_wmem_min=16384"
            "net.ipv4.tcp_notsent_lowat=16384"
            "net.ipv4.tcp_slow_start_after_idle=0"
            "net.ipv4.tcp_fastopen=3"
            "net.ipv4.tcp_mtu_probing=1"
            "net.ipv4.tcp_syncookies=1"
            "net.ipv4.ip_local_port_range=32768 65535"
        )

        sysctl_content="# === 通用代理服务端高并发优化 ===\n"

        for param in "${sysctl_params[@]}"; do
            key="${param%%=*}"
            val="${param#*=}"
            if $SUDO sysctl "$key" >/dev/null 2>&1; then
                sysctl_content+="${key}=${val}\n"
            else
                echo -e "${YELLOW}警告: 内核不支持参数 ${key}，已自动跳过。${NC}"
            fi
        done

        echo -e "${sysctl_content}" | $SUDO tee /etc/sysctl.d/99-sing-box-optimize.conf > /dev/null

        if $SUDO sysctl --system > /dev/null; then
            echo -e "${GREEN}✓ sysctl 网络参数已生效。${NC}"
        else
            echo -e "${YELLOW}警告: sysctl 网络参数在应用时产生部分错误，已自动忽略。${NC}"
        fi
    fi

    $SUDO mkdir -p /etc/security/limits.d
    $SUDO tee /etc/security/limits.d/99-sing-box.conf > /dev/null << 'EOF'

# proxy server: raise open file limit
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
    echo -e "${GREEN}✓ 内核参数与文件描述符(ulimit)优化完成！${NC}"
fi

# 4. 自动创建用户并设置权限
if ! id sing-box &>/dev/null; then
    $SUDO useradd --system --no-create-home --shell /usr/sbin/nologin sing-box
fi
$SUDO mkdir -p /var/lib/sing-box /etc/sing-box
$SUDO chown -R sing-box:sing-box /var/lib/sing-box /etc/sing-box

# 5. 自动生成 Reality 密钥对、UUID 和参数
UUID=$(sing-box generate uuid)
KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey" | awk -F': ' '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep "PublicKey" | awk -F': ' '{print $2}')
[ -n "$UUID" ] || die "UUID 生成失败。"
[ -n "$PRIVATE_KEY" ] || die "Reality 私钥为空，密钥对生成失败。"
[ -n "$PUBLIC_KEY" ] || die "Reality 公钥为空，密钥对生成失败。"
SHORT_ID=$(openssl rand -hex 8)
SERVER_IP="$(get_public_ip)"
SERVER_IP6=""
if ip -6 route show | grep -q "default"; then
    SERVER_IP6=$(curl -6 -s ifconfig.me -m 5 2>/dev/null || echo "")
fi
[ -n "$SERVER_IP" ] || die "无法获取服务器 IPv4 地址，请检查网络后重试。"
if [ "$PROTO_CHOICE" != "2" ]; then
    SOCKS_USER=$(openssl rand -hex 4)
    SOCKS_PASS=$(openssl rand -hex 16)
fi

# SNI 伪装域名列表（支持 TLS 1.3，证书链短且稳定，全球一致性好）
SNI_LIST=(
  "www.cloudflare.com"
  "speed.cloudflare.com"
  "www.samsung.com"
  "www.nvidia.com"
  "www.amd.com"
)
SNI=${SNI_LIST[$RANDOM % ${#SNI_LIST[@]}]}

# 6. 自动写入 JSON 配置文件
cat <<EOF | $SUDO tee /etc/sing-box/config.json > /dev/null
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [
      { "type": "local", "tag": "local" },
      { "type": "udp", "tag": "proxy", "server": "1.1.1.1" }
    ],
    "rules": [
      { "rule_set": "geosite-cn", "server": "local" }
    ],
    "final": "proxy",
    "strategy": "prefer_ipv4"
  },
  "inbounds": [
    {
      "tag": "VLESS-Vision-Reality",
      "type": "vless",
      "listen": "::",
      "listen_port": $VLESS_PORT,
      "users": [ { "uuid": "$UUID", "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "reality": {
          "enabled": true,
          "handshake": { "server": "$SNI", "server_port": 443 },
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    }$(if [ "$PROTO_CHOICE" != "2" ]; then echo ",
    {
      \"tag\": \"SOCKS5-Proxy\",
      \"type\": \"socks\",
      \"listen\": \"::\",
      \"listen_port\": $SOCKS_PORT,
      \"users\": [ { \"username\": \"$SOCKS_USER\", \"password\": \"$SOCKS_PASS\" } ]
    }"; fi)
  ],
  "outbounds": [
    { "tag": "阻断", "type": "block" },
    { "tag": "直接出站", "type": "direct" }
  ],
  "route": {
    "default_domain_resolver": {
      "server": "local",
      "strategy": "prefer_ipv4"
    },
    "rules": [
      { "protocol": "bittorrent", "outbound": "阻断" },
      { "ip_is_private": true, "outbound": "直接出站" },
      { "rule_set": ["geosite-cn", "geoip-cn"], "outbound": "直接出站" }
    ],
    "rule_set": [
      {
        "tag": "geosite-cn", "type": "remote", "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/cn.srs"
      },
      {
        "tag": "geoip-cn", "type": "remote", "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/cn.srs"
      }
    ],
    "final": "直接出站"
  }
}
EOF

# 7. 自动格式化、校验并启动
$SUDO sing-box format -w -c /etc/sing-box/config.json
if $SUDO sing-box check -c /etc/sing-box/config.json; then
    if [[ "$OPTIMIZE_CHOICE" =~ ^[Yy]$ || "$OPTIMIZE_CHOICE" == "" ]]; then
        $SUDO mkdir -p /etc/systemd/system/sing-box.service.d
        $SUDO tee /etc/systemd/system/sing-box.service.d/limits.conf > /dev/null << 'EOF'
[Service]
LimitNOFILE=1048576
EOF
    fi
    $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
    $SUDO systemctl enable --now sing-box
    
    # 8. 自动生成分享链接
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${VLESS_PORT}?type=tcp&encryption=none&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#Auto_Reality"
    if [ -n "$SERVER_IP6" ]; then
        VLESS_LINK6="vless://${UUID}@[${SERVER_IP6}]:${VLESS_PORT}?type=tcp&encryption=none&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#Auto_Reality_IPv6"
    fi

    # 保存到文件
    if [ "$PROTO_CHOICE" != "2" ]; then
        SOCKS_LINK="socks5://${SOCKS_USER}:${SOCKS_PASS}@${SERVER_IP}:${SOCKS_PORT}"
        if [ -n "$SERVER_IP6" ]; then
            SOCKS_LINK6="socks5://${SOCKS_USER}:${SOCKS_PASS}@[${SERVER_IP6}]:${SOCKS_PORT}"
        fi
        install -m 600 /dev/null ~/sing-box.txt
        cat > ~/sing-box.txt <<EOL
==================== VLESS Reality (IPv4) ====================
$VLESS_LINK
$([ -n "$SERVER_IP6" ] && echo -e "\n==================== VLESS Reality (IPv6) ====================\n$VLESS_LINK6")
==================== SOCKS5 代理 (IPv4) ====================
$SOCKS_LINK
$([ -n "$SERVER_IP6" ] && echo -e "\n==================== SOCKS5 代理 (IPv6) ====================\n$SOCKS_LINK6")
==============================================================
EOL
    else
        install -m 600 /dev/null ~/sing-box.txt
        cat > ~/sing-box.txt <<EOL
==================== VLESS Reality (IPv4) ====================
$VLESS_LINK
$([ -n "$SERVER_IP6" ] && echo -e "\n==================== VLESS Reality (IPv6) ====================\n$VLESS_LINK6")
==============================================================
EOL
    fi

    if ! openssl s_client -connect "${SNI}:443" -tls1_3 </dev/null 2>/dev/null | grep -q "TLSv1.3"; then
        echo -e "${YELLOW}警告: 当前 SNI($SNI) 可能不支持 TLS 1.3，建议更换后重试。${NC}"
    fi

    firewall_configured=0

    # 1. 自动配置 UFW 防火墙
    if command -v ufw >/dev/null 2>&1 && $SUDO ufw status | grep -q "Status: active"; then
        $SUDO ufw allow "${VLESS_PORT}/tcp" >/dev/null 2>&1 || true
        if [ "$PROTO_CHOICE" != "2" ]; then
            $SUDO ufw allow "${SOCKS_PORT}/tcp" >/dev/null 2>&1 || true
        fi
        echo -e "${GREEN}✓ UFW 防火墙规则已自动添加${NC}"
        firewall_configured=1
    fi

    # 2. 自动配置 firewalld 防火墙
    if [ "$firewall_configured" -eq 0 ] && command -v firewall-cmd >/dev/null 2>&1 && $SUDO firewall-cmd --state >/dev/null 2>&1; then
        $SUDO firewall-cmd --zone=public --add-port="${VLESS_PORT}/tcp" --permanent >/dev/null 2>&1 || true
        if [ "$PROTO_CHOICE" != "2" ]; then
            $SUDO firewall-cmd --zone=public --add-port="${SOCKS_PORT}/tcp" --permanent >/dev/null 2>&1 || true
        fi
        $SUDO firewall-cmd --reload >/dev/null 2>&1 || true
        echo -e "${GREEN}✓ Firewalld 防火墙规则已自动添加${NC}"
        firewall_configured=1
    fi

    # 3. 自动配置 iptables 与 ip6tables 防火墙
    if [ "$firewall_configured" -eq 0 ] && command -v iptables >/dev/null 2>&1; then
        iptables_changed=0

        # IPv4 放行
        if ! $SUDO iptables -C INPUT -p tcp --dport "$VLESS_PORT" -j ACCEPT >/dev/null 2>&1; then
            $SUDO iptables -I INPUT -p tcp --dport "$VLESS_PORT" -j ACCEPT >/dev/null 2>&1 && iptables_changed=1 || true
        fi
        if [ "$PROTO_CHOICE" != "2" ]; then
            if ! $SUDO iptables -C INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT >/dev/null 2>&1; then
                $SUDO iptables -I INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT >/dev/null 2>&1 && iptables_changed=1 || true
            fi
        fi

        # IPv6 放行
        if command -v ip6tables >/dev/null 2>&1; then
            if ! $SUDO ip6tables -C INPUT -p tcp --dport "$VLESS_PORT" -j ACCEPT >/dev/null 2>&1; then
                $SUDO ip6tables -I INPUT -p tcp --dport "$VLESS_PORT" -j ACCEPT >/dev/null 2>&1 && iptables_changed=1 || true
            fi
            if [ "$PROTO_CHOICE" != "2" ]; then
                if ! $SUDO ip6tables -C INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT >/dev/null 2>&1; then
                    $SUDO ip6tables -I INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT >/dev/null 2>&1 && iptables_changed=1 || true
                fi
            fi
        fi

        # 如果规则发生变更，尝试持久化保存
        if [ "$iptables_changed" -eq 1 ]; then
            # 检测是否有保存工具，如果没有，尝试在主流发行版上自动静默安装
            if ! command -v netfilter-persistent >/dev/null 2>&1; then
                if command -v apt-get >/dev/null 2>&1; then
                    echo "检测到未安装 netfilter-persistent，正在尝试自动安装以持久化防火墙规则..."
                    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | $SUDO debconf-set-selections >/dev/null 2>&1 || true
                    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | $SUDO debconf-set-selections >/dev/null 2>&1 || true
                    $SUDO apt-get update -qq
                    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y iptables-persistent >/dev/null 2>&1 || true
                elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
                    echo "检测到未安装 iptables-services，正在尝试自动安装以持久化防火墙规则..."
                    $SUDO dnf install -y iptables-services >/dev/null 2>&1 || $SUDO yum install -y iptables-services >/dev/null 2>&1 || true
                    $SUDO systemctl enable iptables >/dev/null 2>&1 || true
                    $SUDO systemctl start iptables >/dev/null 2>&1 || true
                fi
            fi

            saved=0
            if command -v netfilter-persistent >/dev/null 2>&1; then
                $SUDO netfilter-persistent save >/dev/null 2>&1 && saved=1 || true
            elif command -v service >/dev/null 2>&1 && $SUDO service iptables-persistent status >/dev/null 2>&1; then
                $SUDO service iptables-persistent save >/dev/null 2>&1 && saved=1 || true
            elif command -v systemctl >/dev/null 2>&1 && $SUDO systemctl is-active iptables >/dev/null 2>&1; then
                $SUDO service iptables save >/dev/null 2>&1 && saved=1 || true
            fi

            if [ "$saved" -eq 1 ]; then
                echo -e "${GREEN}✓ iptables/ip6tables 防火墙规则已自动添加并保存${NC}"
            else
                echo -e "${YELLOW}✓ iptables/ip6tables 防火墙规则已临时添加，但未持久化保存。${NC}"
                echo -e "${YELLOW}提示: 重启后规则可能会失效。建议安装 iptables-persistent (Debian/Ubuntu) 或 iptables-services (CentOS/RHEL) 并手动保存规则。${NC}"
            fi
        else
            echo -e "${GREEN}✓ iptables/ip6tables 防火墙规则已存在，无需重复添加${NC}"
        fi
    fi

    # 打印输出
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${CYAN}自动部署完成！${NC}"
    echo -e "配置已保存至: ~/sing-box.txt"
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}【VLESS Reality - IPv4】${NC}"
    echo -e "$VLESS_LINK"
    if [ -n "$SERVER_IP6" ]; then
        echo -e "${CYAN}==================================================${NC}"
        echo -e "${CYAN}【VLESS Reality - IPv6】${NC}"
        echo -e "$VLESS_LINK6"
    fi
    if [ "$PROTO_CHOICE" != "2" ]; then
        echo -e "${CYAN}==================================================${NC}"
        echo -e "${CYAN}【SOCKS5 代理 - IPv4】${NC}"
        echo -e "$SOCKS_LINK"
        if [ -n "$SERVER_IP6" ]; then
            echo -e "${CYAN}==================================================${NC}"
            echo -e "${CYAN}【SOCKS5 代理 - IPv6】${NC}"
            echo -e "$SOCKS_LINK6"
        fi
    fi
    echo -e "${CYAN}==================================================${NC}"
else
    echo -e "${RED}校验失败，请检查配置文件内容。${NC}"
fi
