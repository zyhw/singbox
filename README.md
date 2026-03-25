# singbox

sing-box 全自动部署 & 升级脚本（1.14.x 分支）。

> ⚠️ 此分支适配 sing-box **1.14.x**，如需使用 1.12.x 稳定版请切换到 [main 分支](https://github.com/zyhw/singbox/tree/main)。

## 一键安装

```bash
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/1.14/sing.sh")
```

## 一键升级

```bash
# 升级到最新 1.14.x
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/1.14/upgrade.sh")

# 升级到指定版本
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/1.14/upgrade.sh") 1.14.1
```

> 升级不会覆盖配置文件，脚本会自动处理版本锁定、校验和服务重启。

## 功能特点
- 自动安装 sing-box 1.14.x 稳定版（版本锁定，防止意外升级）
- 支持 VLESS Reality 配置
- 支持 SOCKS5 代理（随机用户名/密码）
- 自动生成分享链接及配置文件
- 可复用的升级脚本，支持指定版本或通配升级
- 安装与升级提供互动式菜单，可选择官方 apt 源或从 GitHub Releases 下载
- 智能回退机制：GitHub 下载失败会自动安全回退至 apt 软件源

## 相较 1.12 的配置变更
- DNS 服务器格式迁移：新增 `type` 字段（`local` / `udp`）
- 新增 `route.default_domain_resolver` 字段
- 详见 [官方迁移文档](https://sing-box.sagernet.org/migration/#1140)
