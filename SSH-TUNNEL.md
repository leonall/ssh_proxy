# SSH 隧道代理 - 简明部署指南

## 方案概述

```
电脑浏览器/应用  -->  SOCKS5 代理 (本地:7890)  -->  SSH 隧道  -->  海外服务器  -->  目标网站
```

**服务器只需**：OpenSSH（通常已预装）
**本地只需**：SSH 客户端（Windows 10+ / macOS / Linux 内置）

---

## 第一部分：服务器配置

### 1.1 SSH 连接到服务器

```bash
ssh root@你的服务器IP
```

### 1.2 检查 SSH 配置

```bash
grep -E "AllowTcpForwarding|PubkeyAuthentication|PasswordAuthentication" /etc/ssh/sshd_config
```

预期输出（如果有值的话）：
```
AllowTcpForwarding yes
PubkeyAuthentication yes
PasswordAuthentication no
```

### 1.3 编辑 SSH 配置

```bash
vi /etc/ssh/sshd_config
```

找到并修改（没有就添加）：
```ssh-config
AllowTcpForwarding yes
GatewayPorts no
```

如果文件中有 `#PasswordAuthentication yes`，去掉 `#` 改为 `no`
如果文件中有 `#PubkeyAuthentication yes`，去掉 `#`

### 1.4 重启 SSH

```bash
systemctl restart sshd
```

### 1.5 创建代理用户

```bash
# 创建用户
useradd -m -s /usr/sbin/nologin proxyuser

# 创建 SSH 目录
mkdir -p /home/proxyuser/.ssh
chmod 700 /home/proxyuser/.ssh

# 创建授权文件
touch /home/proxyuser/.ssh/authorized_keys
chmod 600 /home/proxyuser/.ssh/authorized_keys
chown -R proxyuser:proxyuser /home/proxyuser/.ssh

echo "用户创建完成"
```

### 1.6 防火墙设置（可选）

如果服务器有防火墙：

```bash
# Ubuntu/Debian
ufw allow 22/tcp
ufw enable

# CentOS
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload
```

---

## 第二部分：本地电脑配置

### 2.1 生成 SSH 密钥

Windows 打开 PowerShell，macOS/Linux 打开终端：

```bash
ssh-keygen -t ed25519 -C "proxy-tunnel"
```

连续按 3 次回车。

### 2.2 上传公钥到服务器

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub proxyuser@你的服务器IP
```

会提示输入密码，输入刚才设置的密码。

### 2.3 验证密钥登录

```bash
ssh proxyuser@你的服务器IP
```

如果能直接登录（不提示输入密码），说明配置成功。

---

## 第三部分：连接使用

### 3.1 建立 SSH 隧道

在本地终端执行：

```bash
ssh -N -D 7890 proxyuser@你的服务器IP
```

- `-N` 不打开远程 Shell
- `-D 7890` 本地端口作为 SOCKS5 代理

### 3.2 后台保持连接

```bash
ssh -N -f -D 7890 proxyuser@你的服务器IP
```

连接后会立即返回终端。

### 3.3 断开连接

```bash
pkill -f "ssh.*-D.*7890"
```

---

## 第四部分：浏览器配置

### Chrome / Edge

1. 设置 > 系统 > 代理设置
2. 手动代理配置
3. SOCKS 主机：`127.0.0.1`，端口：`7890`
4. 保存

### Firefox

1. 设置 > 常规 > 网络设置 > 设置
2. 选择「手动代理配置」
3. SOCKS 主机：`127.0.0.1`，端口：`7890`
4. 选择「SOCKS v5」
5. 勾选「代理 DNS」
6. 确定

### SwitchyOmega（推荐）

Chrome 扩展，可快速切换代理：

1. 安装 SwitchyOmega
2. 新建代理配置
3. 协议：SOCKS5
4. 服务器：`127.0.0.1`
5. 端口：`7890`

---

## 验证测试

### 检查代理是否生效

访问以下网站，应该显示服务器的 IP：

- https://whatismyipaddress.com
- https://ip.sb
- https://ipecho.net

### 测试 Google

```bash
curl -x socks5://127.0.0.1:7890 https://www.google.com
```

---

## 常见问题

### Q: 连接被拒绝

检查：
1. 服务器 IP 是否正确
2. SSH 端口是否默认 22
3. 服务器防火墙是否开放 22 端口

### Q: 隧道断开后无法上网

浏览器代理设置未改回「不使用代理」，改回来即可。

### Q: 如何后台保持？

使用 `screen`：

```bash
# 安装
apt install screen

# 创建会话
screen -S tunnel

# 在会话中执行
ssh -N -D 7890 proxyuser@你的服务器IP

# 断开会话：Ctrl+A D

# 恢复会话
screen -r tunnel
```

---

## 完整命令速查

| 操作 | 命令 |
|------|------|
| 建立隧道 | `ssh -N -D 7890 proxyuser@服务器IP` |
| 后台运行 | `ssh -N -f -D 7890 proxyuser@服务器IP` |
| 断开隧道 | `pkill -f "ssh.*-D.*7890"` |
| 查看进程 | `ps aux \| grep ssh` |
| 测试代理 | `curl -x socks5://127.0.0.1:7890 https://www.google.com` |

---

## 安全建议

1. **服务器 SSH 禁用密码登录**，只用密钥
2. **使用非标准端口**（如 2222）减少扫描
3. **限制代理用户权限**（已设为 nologin）
4. **定期检查日志**：`tail -f /var/log/auth.log`

---

**文档版本**: 1.0
**更新日期**: 2026-04-07
