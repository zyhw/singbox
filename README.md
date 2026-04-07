# singbox

sing-box fully automated deployment & upgrade scripts.

## One-click Installation

```bash
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/main/sing.sh")
```

## One-click Upgrade

```bash
# Upgrade to the latest 1.12.x version
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/main/upgrade.sh")

# Upgrade to a specific version
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/main/upgrade.sh") 1.12.24
```

> The upgrade will not overwrite your configuration files. The script automatically handles version locking, verification, and service restarts.

## One-click Optimization (Kernel & Network)

The one-click installation script already includes optimization options during setup. If you have an existing server and only want to add network and kernel optimizations (BBR, increased concurrent connections, expanded TCP/UDP buffers), you can run this command separately (no reinstallation required):

```bash
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/main/optimize.sh")
```

## Features
- Automatically install sing-box 1.12.x stable version (version-locked to prevent accidental upgrades)
- Supports VLESS Reality configuration
- Supports SOCKS5 proxy (optional: deploy VLESS only, or both with support for randomly assigned user groups)
- Automatically generate sharing links and configuration files
- Reusable upgrade script supporting specific versions or wildcard upgrades
- **New Support: Interactive menu for installation and upgrades, offering choices between official apt source or downloading the latest 1.12.x offline package from GitHub Releases**
- **Intelligent Fallback: Automatically falls back safely to the stable apt software source process if GitHub download times out or fails**
- **Deep Kernel & Network Optimization: Includes a standalone one-click optimization script to address BBR, ulimit, high-bandwidth TCP/UDP buffer bottlenecks, and network backlog queues, significantly boosting server performance.**
