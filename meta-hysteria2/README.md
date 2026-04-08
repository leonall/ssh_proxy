# Clash Meta 直连方案: sing-box + Hysteria2

这套方案是给 `Clash Meta / Mihomo` 直接接入用的，不再依赖本地 SSH 隧道。

## 适用场景

- 你有一台 Linux 服务器
- 你有一个已经解析到服务器公网 IP 的域名
- 你希望 Clash Meta 直接连服务器，而不是先连 SSH 隧道

## 方案特点

- 服务端使用 `sing-box`
- 传输协议使用 `Hysteria2`
- TLS 证书使用 `certbot`
- 客户端配置兼容 `Clash Meta / Mihomo`

## 目录

```text
meta-hysteria2/
├─ README.md
├─ server/
│  ├─ install.sh
│  ├─ sing-box.service
│  └─ config.template.json
└─ client/
   └─ mihomo.yaml.example
```

## 部署前准备

在开始之前，请确认：

1. 服务器系统是 Ubuntu 或 Debian。
2. 域名已经解析到服务器公网 IP。
3. 服务器防火墙允许 `80/tcp`、`443/tcp`、`443/udp`。
4. 80 端口没有被别的程序长期占用，方便 `certbot --standalone` 申请证书。

## 服务端部署

把 `meta-hysteria2/server` 目录上传到服务器，然后执行：

```bash
cd meta-hysteria2/server
chmod +x install.sh
./install.sh your-domain.example.com you@example.com
```

脚本会自动完成这些事情：

- 安装依赖
- 下载最新稳定版 `sing-box`
- 申请 Let's Encrypt 证书
- 生成 `/etc/sing-box/config.json`
- 安装并启动 `systemd` 服务
- 输出客户端需要的密码

## 部署完成后检查

```bash
systemctl status sing-box
journalctl -u sing-box -n 50 --no-pager
ss -tulpn | grep 443
```

如果服务正常，你应该能看到 `sing-box` 正在监听 `443`。

## 客户端配置

把 `client/mihomo.yaml.example` 复制到你的 Clash Meta 配置中，然后替换这几个字段：

- `server`
- `password`
- `obfs-password`
- `sni`

最小示例：

```yaml
proxies:
  - name: "my-hy2"
    type: hysteria2
    server: your-domain.example.com
    port: 443
    password: replace-with-server-password
    obfs: salamander
    obfs-password: replace-with-obfs-password
    sni: your-domain.example.com
    alpn:
      - h3
    skip-cert-verify: false
```

## 常用运维命令

```bash
systemctl restart sing-box
systemctl stop sing-box
systemctl status sing-box
journalctl -u sing-box -f
cat /etc/sing-box/config.json
```

## 更新 sing-box

重新执行安装脚本即可，脚本会重新下载当前最新版本并覆盖 `/usr/local/bin/sing-box`。

```bash
cd meta-hysteria2/server
./install.sh your-domain.example.com you@example.com
```

## 风险和注意事项

- 这套脚本默认使用 `certbot --standalone`，申请证书时会占用 80 端口。
- 如果你的服务器已经有 Nginx/Caddy 在处理证书，建议改用现有证书路径，再手动调整 `config.json`。
- Hysteria2 依赖 UDP，务必确认云厂商安全组和系统防火墙都放行 `443/udp`。
- 如果你所在网络对 UDP 很不友好，可以再补一套 `TUIC` 或 `VLESS-REALITY` 作为备用。
