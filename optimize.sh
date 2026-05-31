#!/bin/bash
set -euo pipefail

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SYSCTL_FILE="/etc/sysctl.d/99-sing-box-optimize.conf"
LIMITS_FILE="/etc/security/limits.d/99-sing-box.conf"
SYSTEMD_DROPIN_DIR="/etc/systemd/system/sing-box.service.d"
SYSTEMD_LIMITS_FILE="${SYSTEMD_DROPIN_DIR}/limits.conf"

rollback() {
    echo -e "${YELLOW}正在回退 sing-box 网络优化配置...${NC}"
    rm -f "${SYSCTL_FILE}" "${LIMITS_FILE}" "${SYSTEMD_LIMITS_FILE}"
    rmdir "${SYSTEMD_DROPIN_DIR}" 2>/dev/null || true
    sysctl --system > /dev/null
    systemctl daemon-reload >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ 已回退本脚本写入的优化配置。${NC}"
}

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}      Linux 服务器高并发与网络性能一键优化脚本      ${NC}"
echo -e "${CYAN}====================================================${NC}"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：本脚本必须以 root 用户运行。请使用 sudo 或切换到 root。${NC}" 
   exit 1
fi

if [ "${1:-}" = "rollback" ]; then
    rollback
    exit 0
fi

echo -e "${YELLOW}正在进行内核网络优化 (包括 BBR, Somaxconn, 缓冲区扩大)...${NC}"

modprobe tcp_bbr 2>/dev/null || true

# 动态缓冲区（总内存 5%，下限 16MB，上限 64MB）
mem_total_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
buf_bytes=$((mem_total_kb * 5 / 100 * 1024))
if [ "$buf_bytes" -lt 16777216 ]; then
    buf_bytes=16777216
fi
if [ "$buf_bytes" -gt 67108864 ]; then
    buf_bytes=67108864
fi
tcp_buf_max=$((buf_bytes / 2))
if [ "$tcp_buf_max" -lt 8388608 ]; then
    tcp_buf_max=8388608
fi

# 配置 sysctl drop-in（幂等覆盖）
cat > "${SYSCTL_FILE}" << EOF

# === 通用代理服务端高并发优化 ===
# BBR（提升拥塞控制与吞吐量）
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# 连接队列抗并发抗D
net.core.somaxconn=4096
net.core.netdev_max_backlog=16384
net.ipv4.tcp_max_syn_backlog=16384

# TCP + UDP 缓冲区放大（按内存动态计算）
net.core.rmem_default=2097152
net.core.rmem_max=${buf_bytes}
net.core.wmem_default=2097152
net.core.wmem_max=${buf_bytes}
net.ipv4.tcp_rmem=4096 87380 ${tcp_buf_max}
net.ipv4.tcp_wmem=4096 65536 ${tcp_buf_max}
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384

# TCP 附加优化
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_syncookies=1
net.ipv4.ip_local_port_range=1024 65535
EOF
echo -e "${GREEN}✓ ${SYSCTL_FILE} 已写入。${NC}"

# 应用 sysctl
sysctl --system > /dev/null
echo -e "${GREEN}✓ sysctl 网络参数已生效。${NC}"

# 配置 limits drop-in（幂等覆盖）
echo -e "${YELLOW}正在扩大系统最大文件描述符限制 (ulimit)...${NC}"
mkdir -p /etc/security/limits.d
cat > "${LIMITS_FILE}" << 'EOF'

# proxy server: raise open file limit
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
echo -e "${GREEN}✓ ${LIMITS_FILE} 已写入。${NC}"

# 让 systemd 启动的 sing-box 服务同步获得 nofile 限制
mkdir -p "${SYSTEMD_DROPIN_DIR}"
cat > "${SYSTEMD_LIMITS_FILE}" << 'EOF'
[Service]
LimitNOFILE=1048576
EOF
systemctl daemon-reload >/dev/null 2>&1 || true

echo -e "${CYAN}====================================================${NC}"
echo -e "${GREEN}服务器网络与内核性能优化完成！${NC}"
echo -e "${GREEN}所有参数均已持久化，重启服务器也不会失效。${NC}"
echo -e "${CYAN}====================================================${NC}"
