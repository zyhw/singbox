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

rollback() {
    echo -e "${YELLOW}正在回退 sing-box 网络优化配置...${NC}"
    rm -f "${SYSCTL_FILE}" "${LIMITS_FILE}" "${SYSTEMD_LIMITS_FILE}"
    rmdir "${SYSTEMD_DROPIN_DIR}" 2>/dev/null || true
    sysctl --system > /dev/null || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl try-restart sing-box >/dev/null 2>&1 || true
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

if is_container; then
    echo -e "${YELLOW}检测到处于容器环境 (LXC/Docker)，无法修改宿主机内核网络参数。${NC}"
    echo -e "${YELLOW}已自动跳过内核网络优化参数配置。${NC}"
    rm -f "${SYSCTL_FILE}"
else
    modprobe tcp_bbr 2>/dev/null || true

    # 动态缓冲区（总内存 5%，下限 16MB，上限 64MB）
    mem_total_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
    buf_bytes=$((mem_total_kb * 5 / 100 * 1024))
    [ "$buf_bytes" -lt 16777216 ] && buf_bytes=16777216
    [ "$buf_bytes" -gt 67108864 ] && buf_bytes=67108864
    tcp_buf_max=$((buf_bytes / 2))
    [ "$tcp_buf_max" -lt 8388608 ] && tcp_buf_max=8388608

    # 待配置的内核参数列表
    sysctl_params=(
        "net.core.default_qdisc=fq"
        "net.ipv4.tcp_congestion_control=bbr"
        "net.core.somaxconn=4096"
        "net.core.netdev_max_backlog=16384"
        "net.ipv4.tcp_max_syn_backlog=16384"
        "net.core.rmem_max=${buf_bytes}"
        "net.core.wmem_max=${buf_bytes}"
        "net.ipv4.tcp_rmem=4096 87380 ${tcp_buf_max}"
        "net.ipv4.tcp_wmem=4096 65536 ${tcp_buf_max}"
        "net.ipv4.udp_rmem_min=16384"
        "net.ipv4.udp_wmem_min=16384"
        "net.ipv4.tcp_notsent_lowat=16384"
        "net.ipv4.tcp_slow_start_after_idle=0"
        "net.ipv4.tcp_fastopen=3"
        "net.ipv4.tcp_mtu_probing=1"
        "net.ipv4.tcp_syncookies=1"
        "net.ipv4.ip_local_port_range=32768 65535"
    )

    # 配置 sysctl drop-in（幂等覆盖）
    echo "# === 通用代理服务端高并发优化 ===" > "${SYSCTL_FILE}"

    for param in "${sysctl_params[@]}"; do
        key="${param%%=*}"
        val="${param#*=}"
        if sysctl "$key" >/dev/null 2>&1; then
            echo "${key}=${val}" >> "${SYSCTL_FILE}"
        else
            echo -e "${YELLOW}警告: 内核不支持参数 ${key}，已自动跳过。${NC}"
        fi
    done
    echo -e "${GREEN}✓ ${SYSCTL_FILE} 已写入。${NC}"

    # 应用 sysctl
    if sysctl --system > /dev/null; then
        echo -e "${GREEN}✓ sysctl 网络参数已生效。${NC}"
    else
        echo -e "${YELLOW}警告: sysctl 网络参数在应用时产生部分错误，已自动忽略。${NC}"
    fi
fi

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
