# 服务转发

自建代理方案，支持公网 IP 直连，适合没有域名但有海外服务器的场景。

## 当前方案

**meta-hysteria-ip** — 公网 IP + 自签名证书 + Hysteria2

- 不需要域名
- 不需要证书申请
- 服务端：`sing-box`
- 客户端：`Clash Meta / Mihomo`
- 协议：Hysteria2 (QUIC/UDP)
- 默认端口：`11234/udp`

详细说明见 [meta-hysteria-ip/README.md](meta-hysteria-ip/README.md)

## 目录结构

```
服务转发/
├── meta-hysteria-ip/          # 当前使用的方案
│   ├── README.md
│   ├── server/
│   │   ├── install.sh         # 服务端安装脚本
│   │   ├── config.template.json
│   │   └── sing-box.service
│   └── client/
│       └── mihomo.yaml        # Clash Meta 客户端配置
│
├── meta-hysteria2/            # 域名方案（备选）
├── server/                    # Clash TUN 方案（老方案）
├── client/
│
└── SSH-TUNNEL.md              # SSH 隧道方案（老方案）
```

## 快速部署（meta-hysteria-ip）

### 1. 服务端

```bash
# 上传 server/ 目录到服务器
cd meta-hysteria-ip/server
chmod +x install.sh
./install.sh <公网IP>
```

### 2. 客户端

1. 把 `meta-hysteria-ip/client/mihomo.yaml` 导入 Clash Verge
2. 修改 `server` 为服务器 IP
3. 修改 `password` 和 `obfs-password`（服务端 install.sh 会输出这两个值）
4. 确认 `skip-cert-verify: true`
5. 点击 Proxy Check 测试连接

### 3. 确认生效

访问 https://ip.sb 或 https://api.ipify.org ，显示的 IP 应为服务器公网 IP。

## 各方案对比

| 方案 | 依赖 | 端口 | 适用场景 |
|------|------|------|----------|
| **meta-hysteria-ip** | 公网 IP | UDP 11234 | 当前生产方案，无需域名 |
| meta-hysteria2 | 域名 | TCP/UDP 443 | 有域名，更规范 |
| server/ | Clash TUN | SSH 隧道 | 老方案，需要 SSH |

## 常见问题

### Clash Verge proxy check 显示 timeout

1. 确认服务端监听：`ss -tulpn | grep sing-box`，应有 UDP 端口监听
2. 确认密码一致：客户端 `password`/`obfs-password` 与服务端 `/etc/sing-box/config.json` 一致
3. 确认 proxy 名称匹配：proxy 组引用的名称与定义一致
4. 确认云安全组放行了 UDP 端口（TCP 通不代表 UDP 通）
5. 国内推荐使用非 443 端口（如 11234），443 容易被 ISP 深度检测封锁

详细排查见 [meta-hysteria-ip/README.md](meta-hysteria-ip/README.md)
