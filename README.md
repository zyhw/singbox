# singbox

sing-box fully automated deployment & upgrade scripts (`1.14.x` branch).

> **Note:** This branch targets **sing-box `1.14.x`**. For `1.12.x`, switch to the [`main` branch](https://github.com/zyhw/singbox/tree/main).

## One-click Installation

```bash
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/1.14/sing.sh")
```

> The installer validates port inputs, supports both root/sudo execution, and aborts safely on critical errors.
> It enforces exact `1.14.x` apt version resolution, validates generated Reality keys/UUID, and stores output credentials with `0600` permissions.
> If a requested port is already in use (or conflicts between VLESS/SOCKS), the installer auto-increments (`+1`) until a free port is found.
> During reinstallation, the script automatically parses your previous config to let you reuse the existing ports, randomize them with an offset (1-100), or input custom ones. It cleans up obsolete firewall rules to prevent security leaks and outputs a final firewall status summary.
> If the GitHub package download succeeds but `dpkg -i` fails, the script automatically falls back to apt installation.
> SOCKS5 credentials are independently generated (not shared with the VLESS UUID).

## One-click Upgrade (Supports 1.12.x → 1.14.x Lossless Migration)

```bash
# Upgrade to the latest 1.14.x version
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/1.14/upgrade.sh")

# Upgrade to a specific version
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/1.14/upgrade.sh") 1.14.4
```

> The upgrade preserves all existing ports, UUIDs, Reality keys, and SOCKS5 credentials. If upgrading from `1.12.x`, the script automatically backs up `/etc/sing-box/config.json` to `/etc/sing-box/config.json.1.12.bak` and migrates legacy `block` outbounds and DNS settings to `1.14.x` rule actions (`sniff` + `reject`) before validating and restarting the service.

## One-click Optimization (Kernel & Network)

The one-click installation script already includes optimization options during setup. If you have an existing server and only want to add network and kernel optimizations (BBR, queue tuning, and memory-aware TCP/UDP buffers), you can run this command separately (no reinstallation required):

```bash
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/1.14/optimize.sh")
```

Rollback command:

```bash
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/1.14/optimize.sh") rollback
```

> The optimization script writes persistent drop-in files:
> - `/etc/sysctl.d/99-sing-box-optimize.conf`
> - `/etc/security/limits.d/99-sing-box.conf`
> - `/etc/systemd/system/sing-box.service.d/limits.conf`
>
> It applies a conservative profile with dynamic buffer sizing (5% of RAM, clamped to 16MB-64MB), plus stable low-risk additions such as `tcp_max_syn_backlog`, `udp_rmem_min/udp_wmem_min`, `tcp_notsent_lowat`, and `tcp_slow_start_after_idle`.
> `LimitNOFILE=1048576` is applied to the `sing-box` systemd service (not only PAM sessions).
> It automatically detects container environments (LXC/Docker) and skips kernel parameter configuration where the host kernel is not writable.
> Each sysctl key is probed before writing — unsupported parameters are silently skipped with a warning, avoiding hard failures.
> The rollback path also restarts the sing-box service so the removed `LimitNOFILE` drop-in takes effect immediately.

## Features
- Automatically install sing-box 1.14.x stable version (version-locked to prevent accidental upgrades)
- Supports VLESS Reality configuration
- Supports SOCKS5 proxy (optional: deploy VLESS only, or both)
- Automatically generate sharing links and configuration files
- Built-in BitTorrent protocol blocking via 1.14+ rule actions (`action: sniff` + `protocol: bittorrent -> action: reject`)
- Reusable upgrade script supporting specific versions, wildcard upgrades, and automatic `1.12.x` → `1.14.x` configuration migration
- Interactive menus for protocol and installation method selection (official apt source or latest 1.14.x package from GitHub Releases)
- GitHub install path uses Releases API tag resolution for stable `v1.14.x` selection
- Intelligent fallback to exact apt `1.14.x` installation if GitHub retrieval/download fails
- Deep kernel and network optimization support (BBR, ulimit, TCP/UDP buffers, network backlog queues)
- Conservative memory-aware optimization profile with rollback support
- Optional post-deploy SNI TLS 1.3 handshake check with warning output
- Auto-add firewall rules (supporting UFW, Firewalld, Iptables, and 1Panel) for selected ports, with automatic removal of obsolete rules on reinstallation
- Automatic port conflict handling (detect occupied ports and shift to next available port), or reuse/randomly shift previously configured ports
- Post-install firewall summary listing active rules for sing-box ports
- Modernized JSON configuration template supporting sing-box 1.14.0+ DNS, route, and rule action specifications (no deprecation warnings)

## Service Management

Basic `systemctl` commands for day-to-day management:

```bash
# View service status
sudo systemctl status sing-box

# Restart the service (after config changes)
sudo systemctl restart sing-box

# Stop the service
sudo systemctl stop sing-box

# Start the service
sudo systemctl start sing-box

# View real-time logs
sudo journalctl -u sing-box -f

# View recent logs (last 50 lines)
sudo journalctl -u sing-box -n 50 --no-pager

# Verify configuration syntax
sudo sing-box check -c /etc/sing-box/config.json

# Format configuration file
sudo sing-box format -w -c /etc/sing-box/config.json

# View version
sing-box version
```
