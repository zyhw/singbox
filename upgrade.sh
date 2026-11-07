#!/bin/bash
set -euo pipefail

# sing-box 升级脚本
# 用法: bash upgrade.sh [目标版本]
# 示例: bash upgrade.sh          → 升级到最新 1.14.x
#       bash upgrade.sh 1.14.4   → 升级到指定版本

CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TARGET_VERSION="${1:-1.14.*}"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    SUDO=""
else
    command -v sudo >/dev/null 2>&1 || { echo -e "${RED}需要 root 权限或 sudo。${NC}" >&2; exit 1; }
    SUDO="sudo"
fi

get_latest_apt_114_version() {
    apt-cache madison sing-box 2>/dev/null \
        | awk '{print $3}' \
        | grep -E '^1\.14\.[0-9]+([-+~].*)?$' \
        | sort -V \
        | tail -n 1
}

install_sing_box_apt_114() {
    local ver
    ver="$(get_latest_apt_114_version)"
    if [ -n "$ver" ]; then
        $SUDO apt-mark unhold sing-box sing-box-beta >/dev/null 2>&1 || true
        if ! $SUDO apt-get install -yq --allow-downgrades --allow-change-held-packages "sing-box=$ver"; then
            $SUDO apt-mark unhold sing-box sing-box-beta >/dev/null 2>&1 || true
            $SUDO apt-get install -yq --allow-downgrades --allow-change-held-packages "sing-box=$ver"
        fi
    else
        echo -e "${RED}apt 源中未找到 sing-box 1.14.x 版本。${NC}" >&2
        exit 1
    fi
}

install_sing_box_apt_exact() {
    local ver="$1"
    $SUDO apt-mark unhold sing-box sing-box-beta >/dev/null 2>&1 || true
    if ! $SUDO apt-get install "sing-box=${ver}" -y --allow-downgrades --allow-change-held-packages; then
        $SUDO apt-mark unhold sing-box sing-box-beta >/dev/null 2>&1 || true
        $SUDO apt-get install "sing-box=${ver}" -y --allow-downgrades --allow-change-held-packages
    fi
}

get_latest_github_version_by_prefix() {
    local prefix="$1"
    local tmp_file
    tmp_file="$(mktemp)"
    if curl -fsSL --connect-timeout 5 --max-time 20 \
        "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=100" \
        -o "$tmp_file"; then
        jq -r '.[].tag_name' "$tmp_file" 2>/dev/null \
            | sed -n "s/^v\\(${prefix//./\\.}\\.[0-9]\\+\\)$/\\1/p" \
            | sort -V \
            | tail -n 1
    fi
    rm -f "$tmp_file"
}

migrate_config_to_114() {
    local cfg="/etc/sing-box/config.json"
    local bak="/etc/sing-box/config.json.1.12.bak"
    local tmp_cfg

    if ! $SUDO test -f "$cfg"; then
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        $SUDO apt-get install -y jq >/dev/null 2>&1 || true
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${YELLOW}警告: 未检测到 jq，跳过配置文件自动迁移检查。${NC}"
        return 0
    fi

    local needs_migration
    needs_migration=$($SUDO jq -r '
        if (any(.dns.servers[]?; has("address") and (has("type") | not))) or
           ((.route | has("default_domain_resolver")) | not) or
           (any(.outbounds[]?; .type == "block")) or
           (any(.route.rules[]?; .outbound == "阻断" or .outbound == "block")) or
           ((any(.route.rules[]?; .protocol != null)) and (any(.route.rules[]?; .action == "sniff") | not))
        then "yes" else "no" end
    ' "$cfg" 2>/dev/null || echo "no")

    if [ "$needs_migration" != "yes" ]; then
        return 0
    fi

    echo -e "${CYAN}检测到 1.12 旧版配置项，正在自动备份并无损迁移至 1.14 规范...${NC}"
    if ! $SUDO test -f "$bak"; then
        $SUDO cp -a "$cfg" "$bak"
        echo -e "${GREEN}✓ 原配置已备份至: ${bak}${NC}"
    fi

    tmp_cfg="$(mktemp)"
    if $SUDO jq '
        (if .dns.servers then
          .dns.servers |= map(
            if (has("address") and (has("type") | not)) then
              if .address == "local" then
                { "type": "local", "tag": (.tag // "local") }
              else
                { "type": "udp", "tag": (.tag // "proxy"), "server": (.address | sub("^udp://"; "")) }
              end
            else . end
          )
        else . end)
        | (if (.route | has("default_domain_resolver") | not) then
            .route.default_domain_resolver = {
              "server": "local",
              "strategy": (.dns.strategy // "prefer_ipv4")
            }
          else . end)
        | (if .outbounds then
            .outbounds |= map(select(.type != "block"))
          else . end)
        | (if .route.rules then
            .route.rules |= map(
              if (.outbound == "阻断" or .outbound == "block") then
                del(.outbound) | . + { "action": "reject" }
              else . end
            )
          else . end)
        | (if (.route.rules and (any(.route.rules[]; .protocol != null)) and (any(.route.rules[]; .action == "sniff") | not)) then
            .route.rules = [{ "action": "sniff" }] + .route.rules
          else . end)
    ' "$cfg" > "$tmp_cfg"; then
        $SUDO tee "$cfg" < "$tmp_cfg" >/dev/null
        rm -f "$tmp_cfg"
        $SUDO sing-box format -w -c "$cfg" 2>/dev/null || true
        echo -e "${GREEN}✓ 配置文件已成功迁移至 1.14 格式（原有端口、UUID、密钥及账密完全保留）。${NC}"
    else
        rm -f "$tmp_cfg"
        echo -e "${YELLOW}警告: 自动迁移配置文件失败，保留原配置文件不变。${NC}"
    fi
}

CURRENT_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}' || true)
echo -e "${CYAN}当前版本: ${CURRENT_VERSION:-未安装}${NC}"
echo -e "${CYAN}目标版本: ${TARGET_VERSION}${NC}"

echo -e "\n请选择升级方式:"
echo "1. 从官方 apt 软件源升级 (推荐)"
echo "2. 从 GitHub 下载最新 release 升级"
read -p "请输入选项 [默认: 1]: " UPGRADE_CHOICE
UPGRADE_CHOICE=${UPGRADE_CHOICE:-1}

# 1. 解除版本锁定
echo "解除版本锁定..."
$SUDO apt-mark unhold sing-box 2>/dev/null || true

# 2. 更新仓库
echo "更新仓库索引..."
$SUDO apt-get update -qq

# 3. 升级
if [ "$UPGRADE_CHOICE" == "2" ]; then
    echo "正在从 GitHub 获取最新的 release 进行升级..."
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        $SUDO apt-get install -y curl jq >/dev/null 2>&1 || true
    fi
    ARCH=$(dpkg --print-architecture)
    if [[ "$TARGET_VERSION" == *"*"* ]]; then
        PREFIX=$(echo "$TARGET_VERSION" | sed 's/\.\*$//')
        GITHUB_LATEST="$(get_latest_github_version_by_prefix "$PREFIX" || true)"
        if [ -z "$GITHUB_LATEST" ]; then
            echo -e "${RED}无法从 GitHub 获取 ${TARGET_VERSION} 的最新版本，回退到 apt 升级...${NC}"
            if [[ "$TARGET_VERSION" == "1.14.*" ]]; then
                install_sing_box_apt_114
                NEW_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
                echo -e "${GREEN}软件源升级成功: ${CURRENT_VERSION:-N/A} → ${NEW_VERSION}${NC}"
            else
                if $SUDO apt-get install "sing-box=${TARGET_VERSION}" -y --allow-downgrades --allow-change-held-packages; then
                    NEW_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
                    echo -e "${GREEN}软件源升级成功: ${CURRENT_VERSION:-N/A} → ${NEW_VERSION}${NC}"
                else
                    echo -e "${RED}软件源中未找到指定版本或升级失败。${NC}"
                    $SUDO apt-mark hold sing-box 2>/dev/null || true
                    exit 1
                fi
            fi
            FETCH_VERSION=""
        else
            FETCH_VERSION="$GITHUB_LATEST"
        fi
    else
        FETCH_VERSION="$TARGET_VERSION"
    fi
    
    if [ -n "$FETCH_VERSION" ]; then
        DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${FETCH_VERSION}/sing-box_${FETCH_VERSION}_linux_${ARCH}.deb"
        FILE_NAME="/tmp/sing-box_${FETCH_VERSION}_linux_${ARCH}.deb"
        echo -e "${CYAN}正在下载: ${DOWNLOAD_URL}${NC}"
        
        if curl -L --fail "$DOWNLOAD_URL" -o "$FILE_NAME"; then
            if $SUDO dpkg -i "$FILE_NAME"; then
                NEW_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
                echo -e "${GREEN}GitHub 升级成功: ${CURRENT_VERSION:-N/A} → ${NEW_VERSION}${NC}"
                rm -f "$FILE_NAME"
            else
                echo -e "${RED}dpkg 安装失败。${NC}"
                rm -f "$FILE_NAME"
                if [[ "$TARGET_VERSION" == *"*"* ]]; then
                    install_sing_box_apt_114
                else
                    install_sing_box_apt_exact "$TARGET_VERSION"
                fi
                NEW_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
                echo -e "${GREEN}软件源升级成功: ${CURRENT_VERSION:-N/A} → ${NEW_VERSION}${NC}"
            fi
        else
            echo -e "${RED}下载失败，回退到 apt 升级...${NC}"
            if [[ "$TARGET_VERSION" == "1.14.*" ]]; then
                install_sing_box_apt_114
                NEW_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
                echo -e "${GREEN}软件源升级成功: ${CURRENT_VERSION:-N/A} → ${NEW_VERSION}${NC}"
            else
                if $SUDO apt-get install "sing-box=${TARGET_VERSION}" -y --allow-downgrades --allow-change-held-packages; then
                    NEW_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
                    echo -e "${GREEN}软件源升级成功: ${CURRENT_VERSION:-N/A} → ${NEW_VERSION}${NC}"
                else
                    echo -e "${RED}软件源升级失败，请检查网络或版本号。${NC}"
                    $SUDO apt-mark hold sing-box 2>/dev/null || true
                    exit 1
                fi
            fi
        fi
    fi
else
    echo "正在从 apt 软件源升级 sing-box..."
    if [[ "$TARGET_VERSION" == "1.14.*" ]]; then
        install_sing_box_apt_114
        NEW_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
        echo -e "${GREEN}软件源升级成功: ${CURRENT_VERSION:-N/A} → ${NEW_VERSION}${NC}"
    else
        if $SUDO apt-get install "sing-box=${TARGET_VERSION}" -y --allow-downgrades --allow-change-held-packages; then
            NEW_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}' || true)
            echo -e "${GREEN}软件源升级成功: ${CURRENT_VERSION:-N/A} → ${NEW_VERSION}${NC}"
        else
            echo -e "${RED}升级失败，请检查版本号是否正确。${NC}"
            $SUDO apt-mark hold sing-box 2>/dev/null || true
            exit 1
        fi
    fi
fi

# 4. 重新锁定版本
echo "重新锁定版本..."
$SUDO apt-mark hold sing-box

# 5. 自动检测并迁移 1.12 旧版配置至 1.14 规范
migrate_config_to_114

# 6. 校验配置 & 重启
if $SUDO sing-box check -c /etc/sing-box/config.json; then
    $SUDO systemctl restart sing-box
    echo -e "${GREEN}服务已重启，运行正常。${NC}"
else
    echo -e "${RED}配置校验失败！服务未重启，请检查配置文件（备份文件位于 /etc/sing-box/config.json.1.12.bak）。${NC}"
    exit 1
fi

echo -e "${CYAN}升级完成。${NC}"
