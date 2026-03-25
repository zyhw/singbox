#!/bin/bash

# sing-box 升级脚本
# 用法: bash upgrade.sh [目标版本]
# 示例: bash upgrade.sh          → 升级到最新 1.12.x
#       bash upgrade.sh 1.12.24  → 升级到指定版本

CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TARGET_VERSION="${1:-1.12.*}"

# 如果指定了具体版本号（不含通配符），补全为 apt 包格式
if [[ "$TARGET_VERSION" != *"*"* ]]; then
    TARGET_VERSION="${TARGET_VERSION}"
fi

CURRENT_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
echo -e "${CYAN}当前版本: ${CURRENT_VERSION:-未安装}${NC}"
echo -e "${CYAN}目标版本: ${TARGET_VERSION}${NC}"

echo -e "\n请选择升级方式:"
echo "1. 从官方 apt 软件源升级 (推荐)"
echo "2. 从 GitHub 下载最新 release 升级"
read -p "请输入选项 [默认: 1]: " UPGRADE_CHOICE
UPGRADE_CHOICE=${UPGRADE_CHOICE:-1}

# 1. 解除版本锁定
echo "解除版本锁定..."
sudo apt-mark unhold sing-box 2>/dev/null

# 2. 更新仓库
echo "更新仓库索引..."
sudo apt-get update -qq

# 3. 升级
if [ "$UPGRADE_CHOICE" == "2" ]; then
    echo "正在从 GitHub 获取最新的 release 进行升级..."
    ARCH=$(dpkg --print-architecture)
    if [[ "$TARGET_VERSION" == *"*"* ]]; then
        PREFIX=$(echo "$TARGET_VERSION" | sed 's/\.\*$//')
        GITHUB_LATEST=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/tags?per_page=100" | grep -o "\"name\": \"v${PREFIX}\.[0-9]*\"" | grep -o "${PREFIX}\.[0-9]*" | sort -V | tail -n 1)
        if [ -z "$GITHUB_LATEST" ]; then
            echo -e "${RED}无法从 GitHub 获取 ${TARGET_VERSION} 的最新版本，回退到 apt 升级...${NC}"
            if sudo apt-get install "sing-box=${TARGET_VERSION}" -y; then
                NEW_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
                echo -e "${GREEN}软件源升级成功: ${CURRENT_VERSION:-N/A} → ${NEW_VERSION}${NC}"
            else
                echo -e "${RED}软件源中未找到指定版本或升级失败。${NC}"
                sudo apt-mark hold sing-box 2>/dev/null
                exit 1
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
            if sudo dpkg -i "$FILE_NAME"; then
                NEW_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
                echo -e "${GREEN}GitHub 升级成功: ${CURRENT_VERSION:-N/A} → ${NEW_VERSION}${NC}"
                rm -f "$FILE_NAME"
            else
                echo -e "${RED}dpkg 安装失败。${NC}"
                sudo apt-mark hold sing-box 2>/dev/null
                rm -f "$FILE_NAME"
                exit 1
            fi
        else
            echo -e "${RED}下载失败，回退到 apt 升级...${NC}"
            if sudo apt-get install "sing-box=${TARGET_VERSION}" -y; then
                NEW_VERSION=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
                echo -e "${GREEN}软件源升级成功: ${CURRENT_VERSION:-N/A} → ${NEW_VERSION}${NC}"
            else
                echo -e "${RED}软件源升级失败，请检查网络或版本号。${NC}"
                sudo apt-mark hold sing-box 2>/dev/null
                exit 1
            fi
        fi
    fi
else
    echo "正在从 apt 软件源升级 sing-box..."
    if sudo apt-get install "sing-box=${TARGET_VERSION}" -y; then
        NEW_VERSION=$(sing-box version | head -1 | awk '{print $NF}')
        echo -e "${GREEN}软件源升级成功: ${CURRENT_VERSION:-N/A} → ${NEW_VERSION}${NC}"
    else
        echo -e "${RED}升级失败，请检查版本号是否正确。${NC}"
        sudo apt-mark hold sing-box 2>/dev/null
        exit 1
    fi
fi

# 4. 重新锁定版本
echo "重新锁定版本..."
sudo apt-mark hold sing-box

# 5. 校验配置 & 重启
if sudo sing-box check -c /etc/sing-box/config.json; then
    sudo systemctl restart sing-box
    echo -e "${GREEN}服务已重启，运行正常。${NC}"
else
    echo -e "${RED}配置校验失败！服务未重启，请检查配置文件。${NC}"
    exit 1
fi

echo -e "${CYAN}升级完成。${NC}"
