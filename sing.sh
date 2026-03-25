#!/bin/bash

# 定义颜色
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}正在开始 sing-box 全自动部署...${NC}"

# 端口配置（可自定义，回车使用默认值）
read -p "请输入 VLESS 端口 [默认: 443]: " VLESS_PORT
VLESS_PORT=${VLESS_PORT:-443}
read -p "请输入 SOCKS5 端口 [默认: 1080]: " SOCKS_PORT
SOCKS_PORT=${SOCKS_PORT:-1080}

echo -e "\n请选择 sing-box 安装方式:"
echo "1. 从官方 apt 软件源安装 (推荐, 由源决定具体版本)"
echo "2. 从 GitHub 下载最新的 1.14.x Release 离线安装"
read -p "请输入选项 [默认: 1]: " INSTALL_CHOICE
INSTALL_CHOICE=${INSTALL_CHOICE:-1}

# 1. 自动清理冲突版本 (解决 dpkg 报错)
echo "正在检查并清理旧版本..."
sudo systemctl stop sing-box &>/dev/null
sudo apt-get remove --purge sing-box sing-box-beta -y &>/dev/null
sudo apt-get autoremove -y &>/dev/null

# 2. 安装依赖并配置官方仓库
sudo apt-get update -qq
sudo apt-get install -y curl jq uuid-runtime openssl
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
sudo chmod a+r /etc/apt/keyrings/sagernet.asc

echo "Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc" | sudo tee /etc/apt/sources.list.d/sagernet.sources > /dev/null

sudo apt-get update -qq

if [ "$INSTALL_CHOICE" == "2" ]; then
    echo "正在从 GitHub 获取最新的 sing-box 1.14.x 版本..."
    ARCH=$(dpkg --print-architecture)
    GITHUB_LATEST=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/tags?per_page=100" | grep -o '"name": "v1\.14\.[0-9]*"' | grep -o '1\.14\.[0-9]*' | sort -V | tail -n 1)
    if [ -z "$GITHUB_LATEST" ]; then
        echo -e "${RED}无法从 GitHub 获取最新版本，自动回退到 apt 软件源安装...${NC}"
        sudo apt-get install sing-box=1.14.* -yq || sudo apt-get install sing-box -yq
    else
        DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${GITHUB_LATEST}/sing-box_${GITHUB_LATEST}_linux_${ARCH}.deb"
        FILE_NAME="/tmp/sing-box_${GITHUB_LATEST}_linux_${ARCH}.deb"
        echo "正在下载: ${DOWNLOAD_URL}"
        if curl -L --fail "$DOWNLOAD_URL" -o "$FILE_NAME"; then
            sudo dpkg -i "$FILE_NAME"
            rm -f "$FILE_NAME"
        else
            echo -e "${RED}包下载失败，自动回退到 apt 软件源安装...${NC}"
            sudo apt-get install sing-box=1.14.* -yq || sudo apt-get install sing-box -yq
        fi
    fi
else
    echo "正在从 apt 软件源安装 sing-box 1.14.x 稳定版..."
    # 安装 1.14.x 版本
    sudo apt-get install sing-box=1.14.* -yq || sudo apt-get install sing-box -yq
fi

# 锁定版本，避免被 apt upgrade 自动升级掉
sudo apt-mark hold sing-box 2>/dev/null

# 如果以后想解锁升级，运行：
# sudo apt-mark unhold sing-box
# sudo apt-get update && sudo apt-get upgrade sing-box

# 3. 自动创建用户并设置权限
if ! id sing-box &>/dev/null; then
    sudo useradd --system --no-create-home --shell /usr/sbin/nologin sing-box
fi
sudo mkdir -p /var/lib/sing-box /etc/sing-box
sudo chown -R sing-box:sing-box /var/lib/sing-box /etc/sing-box

# 4. 自动生成 Reality 密钥对、UUID 和参数
UUID=$(sing-box generate uuid)
KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey" | awk -F': ' '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep "PublicKey" | awk -F': ' '{print $2}')
SHORT_ID=$(openssl rand -hex 8)
SERVER_IP=$(curl -4 -s ifconfig.me)
SOCKS_USER=$(openssl rand -hex 4)
SOCKS_PASS="$UUID"

# SNI 伪装域名列表（美国服务器 + 中国访问友好）
SNI_LIST=(
  "www.microsoft.com"
  "www.cloudflare.com"
  "www.amd.com"
  "www.nvidia.com"
  "www.tesla.com"
)
SNI=${SNI_LIST[$RANDOM % ${#SNI_LIST[@]}]}

# 5. 自动写入 JSON 配置文件
cat <<EOF | sudo tee /etc/sing-box/config.json > /dev/null
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
    "strategy": "ipv4_only"
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
    },
    {
      "tag": "SOCKS5-Proxy",
      "type": "socks",
      "listen": "::",
      "listen_port": $SOCKS_PORT,
      "users": [ { "username": "$SOCKS_USER", "password": "$SOCKS_PASS" } ]
    }
  ],
  "outbounds": [
    { "tag": "直接出站", "type": "direct" }
  ],
  "route": {
    "default_domain_resolver": {
      "server": "local",
      "strategy": "ipv4_only"
    },
    "rules": [
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

# 6. 自动格式化、校验并启动
sudo sing-box format -w -c /etc/sing-box/config.json
if sudo sing-box check -c /etc/sing-box/config.json; then
    sudo systemctl enable --now sing-box
    
    # 7. 自动生成分享链接
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${VLESS_PORT}?type=tcp&encryption=none&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#Auto_Reality"
    
    # SOCKS5 链接
    SOCKS_LINK="socks5://${SOCKS_USER}:${SOCKS_PASS}@${SERVER_IP}:${SOCKS_PORT}"
    
    # 保存到文件
    cat > ~/sing-box.txt <<EOL
==================== VLESS Reality ====================
$VLESS_LINK

==================== SOCKS5 代理 ====================
$SOCKS_LINK
========================================================
EOL

    # 打印输出
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${CYAN}自动部署完成！${NC}"
    echo -e "配置已保存至: ~/sing-box.txt"
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}【VLESS Reality】${NC}"
    echo -e "$VLESS_LINK"
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}【SOCKS5 代理】${NC}"
    echo -e "$SOCKS_LINK"
    echo -e "${CYAN}==================================================${NC}"
else
    echo -e "${RED}校验失败，请检查配置文件内容。${NC}"
fi
