# singbox

sing-box fully automated deployment & upgrade scripts.

## One-click Installation

```bash
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/main/sing.sh")
```

> The installer validates port inputs, supports both root/sudo execution, and aborts safely on critical errors.

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

> The optimization script writes persistent drop-in files:
> - `/etc/sysctl.d/99-sing-box-optimize.conf`
> - `/etc/security/limits.d/99-sing-box.conf`

## Features
- Automatically install sing-box 1.12.x stable version (version-locked to prevent accidental upgrades)
- Supports VLESS Reality configuration
- Supports SOCKS5 proxy (optional: deploy VLESS only, or both)
- Automatically generate sharing links and configuration files
- Built-in BitTorrent protocol blocking rule (`protocol: bittorrent -> outbound: block`)
- Reusable upgrade script supporting specific versions or wildcard upgrades
- Interactive menus for protocol and installation method selection (official apt source or latest 1.12.x package from GitHub Releases)
- Intelligent fallback to apt installation if GitHub retrieval/download fails
- Deep kernel and network optimization support (BBR, ulimit, TCP/UDP buffers, network backlog queues)
