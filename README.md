# SSH Tunnel + Clash 远程代理服务

基于 SSH 隧道 + Clash 的安全远程代理服务，支持智能分流和多用户。

## 架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户本地环境                              │
│   Clash 客户端 (port: 7890)                                      │
│         │                                                        │
│         │ HTTP/SOCKS5                                            │
│         ▼                                                        │
│   SSH Tunnel (本地端口转发)                                       │
│   ssh -L 7890:127.0.0.1:7890 user@server                        │
└─────────────────────────────┬───────────────────────────────────┘
                              │ SSH 加密隧道
┌─────────────────────────────┴───────────────────────────────────┐
│                        海外服务器                                │
│         │                                                        │
│         ▼                                                        │
│   Clash Server (port: 7890)                                      │
│         │                                                        │
│         ▼                                                        │
│   智能分流 (GeoIP)                                               │
│    ├── 国内 IP → Direct 直连                                     │
│    └── 海外 IP → 代理出口                                         │
└─────────────────────────────────────────────────────────────────┘
```

## 目录结构

```
服务转发/
├── server/                    # 服务器端文件
│   ├── config.yaml           # Clash 服务配置
│   ├── clash.service         # systemd 服务文件
│   ├── sshd_config.patch     # SSH 安全配置补丁
│   └── deploy.sh             # 一键部署脚本
│
├── client/                    # 客户端文件
│   ├── config.yaml           # Clash 客户端配置
│   ├── connect.sh            # SSH 隧道连接脚本
│   └── disconnect.sh         # 断开隧道脚本
│
└── README.md                 # 本文档
```

## 快速开始

### 1. 服务器部署

```bash
# 1. 通过 SSH 连接到海外服务器
ssh root@your-server-ip

# 2. 创建工作目录并上传文件
mkdir -p /opt/clash-deploy
# 将 server/ 目录下的文件上传到服务器

# 3. 运行部署脚本
chmod +x deploy.sh
./deploy.sh

# 4. 上传 SSH 公钥 (在本地执行)
ssh-copy-id -i ~/.ssh/id_ed25519.pub proxyuser@your-server-ip

# 5. 重启 SSH 服务
systemctl restart sshd
```

### 2. 客户端配置

```bash
# 1. 生成 SSH 密钥 (如果还没有)
ssh-keygen -t ed25519 -C "your_email@example.com"

# 2. 上传公钥到服务器
ssh-copy-id -i ~/.ssh/id_ed25519.pub proxyuser@your-server-ip

# 3. 测试 SSH 隧道
chmod +x connect.sh
./connect.sh proxyuser your-server-ip 22

# 4. 配置本地 Clash
# 将 client/config.yaml 复制到 ~/.config/clash/config.yaml
# 或在 Clash 客户端中导入配置

# 5. 启动 Clash 客户端并测试
```

### 3. 验证

```bash
# 测试代理
curl -x http://127.0.0.1:7890 https://www.google.com

# DNS 泄露测试
# 访问 https://ipleak.net 查看 IP 信息
```

## 配置说明

### 服务器端口

| 端口 | 用途 |
|------|------|
| 22 | SSH 远程连接 |
| 7890 | Clash HTTP 代理 (通过 SSH 隧道访问) |
| 7891 | Clash SOCKS5 代理 (通过 SSH 隧道访问) |
| 9090 | Clash RESTful API (仅本地) |

### 多用户配置

为每个用户创建独立端口：

```bash
# 用户 A (端口 7890)
mkdir -p /etc/clash/user_a
# 配置 config.yaml, port: 7890

# 用户 B (端口 7891)
mkdir -p /etc/clash/user_b
# 配置 config.yaml, port: 7891

# 启动
su - clash -s /bin/bash -c "/usr/local/bin/clash -d /etc/clash/user_a -f /etc/clash/user_a/config.yaml &"
```

### SSH 隧道连接

```bash
# 基本连接
ssh -N -L 7890:127.0.0.1:7890 proxyuser@your-server-ip

# 带持久化 (后台运行, 自动重连)
ssh -N -f -o ServerAliveInterval=60 -o ServerAliveCountMax=3 \
    -L 7890:127.0.0.1:7890 proxyuser@your-server-ip

# 查看运行中的隧道
ps aux | grep "ssh.*-L"

# 断开隧道
pkill -f "ssh.*-L.*7890"
```

## 安全建议

1. **使用 SSH 公钥认证**, 禁用密码登录
2. **配置 Fail2ban** 防止 SSH 暴力破解
3. **防火墙只开放 SSH**, 禁用 Ping
4. **定期更新** 系统和 Clash 版本
5. **使用非 root 用户** 运行 Clash

## 常见问题

### Q: SSH 隧道断开怎么办?
A: 使用 `-o ServerAliveInterval=60` 参数，或使用 `connect.sh` 脚本自动重连。

### Q: Clash 服务启动失败?
A: 检查日志: `journalctl -u clash --no-pager -n 50`

### Q: 如何查看 Clash 配置是否正确?
A: `curl http://127.0.0.1:9090/proxies` (需要开启 external-controller)

### Q: 国内网站访问慢?
A: 检查 GeoIP 数据库是否最新，确保 DNS 分流规则完整。

## License

MIT
