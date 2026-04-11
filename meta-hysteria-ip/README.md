# Clash Meta 直连方案: 公网 IP + 自签名证书 + Hysteria2

这套方案专门给只有公网 IP、没有域名的场景准备。

特点:

- 不需要域名
- 不需要 certbot
- 不需要额外花钱
- 服务端使用 `sing-box`
- 客户端使用 `Clash Meta / Mihomo`

适合你这种自己买服务器、自己使用的情况。

## 目录

```text
meta-hysteria2-ip/
├─ README.md
├─ server/
│  ├─ install.sh
│  ├─ config.template.json
│  └─ sing-box.service
└─ client/
   └─ mihomo.yaml
```

## 前提条件

1. 你有一台 Ubuntu 或 Debian 服务器
2. 你知道服务器公网 IP
3. 云厂商安全组和系统防火墙放行:
   - `443/tcp` (仅当你使用 443 端口时才需要)
   - `11234/udp` (默认推荐端口)

## 服务端部署

把 `meta-hysteria2-ip/server` 上传到服务器，执行:

```bash
cd meta-hysteria2-ip/server
chmod +x install.sh
./install.sh 你的公网IP
```

例如:

```bash
./install.sh 1.2.3.4
```

脚本会自动完成:

- 安装依赖
- 下载最新 sing-box
- 生成带 IP SAN 的自签名证书
- 生成 `/etc/sing-box/config.json`
- 安装并启动 `systemd` 服务
- 输出客户端要填写的密码

## 部署后检查

```bash
systemctl status sing-box
journalctl -u sing-box -n 50 --no-pager
ss -tulpn | grep sing-box
```

## 客户端配置

把 [mihomo.yaml](../client/mihomo.yaml) 复制到 Clash Meta 配置里，然后替换:

- `server` (服务器 IP)
- `password` (服务端输出的认证密码)
- `obfs-password` (服务端输出的 obfs 密码)

重点是必须保留:

```yaml
skip-cert-verify: true
```

因为这是自签名证书。

> 注意：proxy 组里引用的 proxy 名称必须与上面定义的 `name` 一致，否则 Clash Verge 会报 timeout。

## 最小客户端示例

```yaml
proxies:
  - name: "my-hy2-ip"
    type: hysteria2
    server: 1.2.3.4
    port: 11234
    password: replace-with-server-password
    obfs: salamander
    obfs-password: replace-with-obfs-password
    sni: 1.2.3.4
    alpn:
      - h3
    skip-cert-verify: true
```

## 常用运维命令

```bash
systemctl restart sing-box
systemctl stop sing-box
systemctl status sing-box
journalctl -u sing-box -f
cat /etc/sing-box/config.json
ls -l /etc/sing-box/certs/
```

## 风险和注意事项

- 自签名证书更适合自用，不适合公开分发给别人
- 客户端必须开启 `skip-cert-verify: true`
- Hysteria2 依赖 UDP，务必确认云安全组已放行对应 UDP 端口
- **国内推荐使用非 443 端口**（如 11234），443 端口容易被 ISP 深度检测封锁
- 如果后面你愿意买域名，再切回公信证书方案会更规范

## 常见问题排查

### Clash Verge proxy check 显示 timeout

1. **确认服务端监听正常**：`ss -tulpn | grep sing-box`，应有 `11234/udp` 监听
2. **确认密码一致**：客户端 `password` 和 `obfs-password` 必须与服务端 `/etc/sing-box/config.json` 完全一致
3. **确认 proxy 名称匹配**：客户端 proxy 组里引用的名称必须与上面定义的 `name` 一致
4. **确认云安全组放行了 UDP 端口**：TCP 443 通不代表 UDP 11234 通，两者都要放行
5. **确认云厂商对 UDP 入站没有策略限制**：部分云厂商默认禁止 UDP 入站，需要联系客服确认

### 如何快速验证 UDP 通道是否通畅

在服务器上用 Python 监听：

```bash
# 服务器监听
nc -ul 11234

# 或用 python
python3 -c "import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind(('0.0.0.0',11234)); print('Listening...'); s.recvfrom(4096)"
```

在客户端发送 UDP 包：

```bash
# Windows/Linux 发送测试包
echo "test" | nc -u 1.2.3.4 11234
```

如果服务器收到包，说明 UDP 通道正常，问题在 Hysteria2 协议配置本身；如果收不到包，说明 UDP 在网络路径上被封锁。
