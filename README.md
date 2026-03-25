# singbox

sing-box 全自动部署 & 升级脚本。

## 一键安装

```bash
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/main/sing.sh")
```

## 一键升级

```bash
# 升级到最新 1.12.x
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/main/upgrade.sh")

# 升级到指定版本
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/main/upgrade.sh") 1.12.24
```

> 升级不会覆盖配置文件，脚本会自动处理版本锁定、校验和服务重启。

## 功能特点
- 自动安装 sing-box 1.12.x 稳定版（版本锁定，防止意外升级）
- 支持 VLESS Reality 配置
- 支持 SOCKS5 代理（随机用户名/密码）
- 自动生成分享链接及配置文件
- 可复用的升级脚本，支持指定版本或通配升级
- **全新支持：安装与升级提供互动式菜单，可自由选择官方 apt 源或从 GitHub Releases 下载最新 1.12.x 离线包安装**
- **智能回退机制：GitHub 下载超时或失败会自动安全回退至稳定的 apt 软件源流程**
