# singbox

sing-box fully automated deployment & upgrade scripts.

## One-click Installation

```bash
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/main/sing.sh")
```

> The installer validates port inputs, supports both root/sudo execution, and aborts safely on critical errors.
> It now enforces exact `1.12.x` apt version resolution, validates generated Reality keys/UUID, and stores output credentials with `0600` permissions.

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
>
> During one-click installation (when optimization is enabled), the script also writes:
> - `/etc/systemd/system/sing-box.service.d/limits.conf`
>
> This ensures `LimitNOFILE=1048576` is applied to the `sing-box` systemd service (not only PAM sessions).

## Features
- Automatically install sing-box 1.12.x stable version (version-locked to prevent accidental upgrades)
- Supports VLESS Reality configuration
- Supports SOCKS5 proxy (optional: deploy VLESS only, or both)
- Automatically generate sharing links and configuration files
- Built-in BitTorrent protocol blocking rule (`protocol: bittorrent -> outbound: block`)
- Reusable upgrade script supporting specific versions or wildcard upgrades
- Interactive menus for protocol and installation method selection (official apt source or latest 1.12.x package from GitHub Releases)
- GitHub install path uses Releases API tag resolution for stable `v1.12.x` selection
- Intelligent fallback to exact apt `1.12.x` installation if GitHub retrieval/download fails
- Deep kernel and network optimization support (BBR, ulimit, TCP/UDP buffers, network backlog queues)
- Optional post-deploy SNI TLS 1.3 handshake check with warning output
- Auto-add UFW allow rules for selected ports when UFW is active
