# sing-box 自动部署脚本维护指南 (MAINTENANCE)

本项目包含一个用于全自动部署 `sing-box` (VLESS Reality & SOCKS5) 的脚本。

## 关键文件
- `sing.sh`: 核心部署脚本。
- `upgrade.sh`: 可复用的升级脚本。
- `.gitignore`: 忽略了 `.DS_Store` 和备份文件。

## 已执行的关键操作 (2026-02-04)
1. **初始化 Git 仓库**: 移除了本地无关文件 (如 `.DS_Store`)。
2. **随机化 SOCKS 用户名**: 修改了脚本，从硬编码的 `admin` 改为 `openssl rand -hex 4` 生成随机用户名。
3. **远程推送**: 已将代码推送至 `git@github.com:zyhw/singbox.git`。
   - 注意：执行了强制推送 (`--force`) 以确保本地新更改覆盖了旧的手动提交。

## 已执行的关键操作 (2026-03-12)
1. **新增升级脚本 `upgrade.sh`**: 用于将 sing-box 从旧版本升级到最新 1.12.x 或指定版本，自动处理解锁/升级/锁定/校验/重启。

## 升级说明
在服务器上执行：
```bash
# 升级到最新 1.12.x
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/main/upgrade.sh")

# 升级到指定版本
bash <(curl -sL "https://raw.githubusercontent.com/zyhw/singbox/refs/heads/main/upgrade.sh") 1.12.24
```
脚本会自动：解除版本锁定 → 升级 → 重新锁定 → 校验配置 → 重启服务。配置文件不受影响。

## 后续维护建议
- **更新脚本**: 若需修改配置（如端口、伪装域名），直接修改 `sing.sh` 后执行 `git commit` 与 `git push`。
- **配置查看**: 部署完成后，具体参数保存在服务器的 `~/sing-box.txt` 中。
