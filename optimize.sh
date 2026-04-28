#!/bin/bash
set -euo pipefail

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}      Linux 服务器高并发与网络性能一键优化脚本      ${NC}"
echo -e "${CYAN}====================================================${NC}"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：本脚本必须以 root 用户运行。请使用 sudo 或切换到 root。${NC}" 
   exit 1
fi

echo -e "${YELLOW}正在进行内核网络优化 (包括 BBR, Somaxconn, 缓冲区扩大)...${NC}"

# 配置 sysctl drop-in（幂等覆盖）
cat > /etc/sysctl.d/99-sing-box-optimize.conf << 'EOF'

# === 通用代理服务端高并发优化 ===
# BBR（提升拥塞控制与吞吐量）
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# 连接队列抗并发抗D
net.core.somaxconn=4096
net.core.netdev_max_backlog=16384

# TCP + UDP 缓冲区放大（大幅提升高带宽跨境传输性能，上限约64MB）
net.core.rmem_default=26214400
net.core.rmem_max=67108864
net.core.wmem_default=26214400
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 65536 33554432

# TCP 附加优化
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_syncookies=1
net.ipv4.ip_local_port_range=1024 65535
EOF
echo -e "${GREEN}✓ /etc/sysctl.d/99-sing-box-optimize.conf 已写入。${NC}"

# 应用 sysctl
sysctl --system > /dev/null
echo -e "${GREEN}✓ sysctl 网络参数已生效。${NC}"

# 配置 limits drop-in（幂等覆盖）
echo -e "${YELLOW}正在扩大系统最大文件描述符限制 (ulimit)...${NC}"
mkdir -p /etc/security/limits.d
cat > /etc/security/limits.d/99-sing-box.conf << 'EOF'

# proxy server: raise open file limit
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
echo -e "${GREEN}✓ /etc/security/limits.d/99-sing-box.conf 已写入。${NC}"

# 重新加载 systemd 以使得 limits 可能的影响生效
systemctl daemon-reload >/dev/null 2>&1

echo -e "${CYAN}====================================================${NC}"
echo -e "${GREEN}服务器网络与内核性能优化完成！${NC}"
echo -e "${GREEN}所有参数均已持久化，重启服务器也不会失效。${NC}"
echo -e "${CYAN}====================================================${NC}"
