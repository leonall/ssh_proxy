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
   └─ mihomo.yaml.example
```

## 前提条件

1. 你有一台 Ubuntu 或 Debian 服务器
2. 你知道服务器公网 IP
3. 云厂商安全组和系统防火墙放行:
   - `443/tcp`
   - `443/udp`

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
ss -tulpn | grep 443
```

## 客户端配置

把 [mihomo.yaml.example](/D:/Test/服务转发/meta-hysteria2-ip/client/mihomo.yaml.example) 复制到 Clash Meta 配置里，然后替换:

- `server`
- `password`
- `obfs-password`
- `sni`

重点是必须保留:

```yaml
skip-cert-verify: true
```

因为这是自签名证书。

## 最小客户端示例

```yaml
proxies:
  - name: "my-hy2-ip"
    type: hysteria2
    server: 1.2.3.4
    port: 443
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
- Hysteria2 依赖 UDP，务必确认 `443/udp` 已放行
- 如果后面你愿意买域名，再切回公信证书方案会更规范
