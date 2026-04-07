# SSH Tunnel + Clash 远程代理服务 - 详细部署指南

## 目录

1. [方案概述](#1-方案概述)
2. [环境要求](#2-环境要求)
3. [服务器部署](#3-服务器部署)
4. [客户端配置](#4-客户端配置)
5. [连接使用](#5-连接使用)
6. [多用户配置](#6-多用户配置)
7. [安全加固](#7-安全加固)
8. [故障排除](#8-故障排除)
9. [日常维护](#9-日常维护)

---

## 1. 方案概述

### 1.1 工作原理

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              完整数据流                                      │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  本地浏览器/应用                                                            │
│        │                                                                    │
│        ▼ [HTTP/SOCKS5 127.0.0.1:7890]                                     │
│  Clash 客户端 ──────────────────────────────────────────────────────────    │
│        │                                                                    │
│        │ [本地端口转发]                                                     │
│        ▼                                                                    │
│  SSH Tunnel (加密隧道)                                                     │
│  ssh -L 7890:127.0.0.1:7890 user@server                                   │
│        │                                                                    │
│        │ [互联网传输 - 加密]                                               │
│        ▼                                                                    │
│  海外服务器                                                                │
│        │                                                                    │
│        ▼                                                                    │
│  Clash 服务端                                                              │
│        │                                                                    │
│        ├─── GeoIP 规则 ──── 国内 IP ──── Direct ──── 直连目标              │
│        │                                                                    │
│        └─── GeoIP 规则 ──── 海外 IP ──── Proxy ──── 代理出口              │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 核心技术

| 技术 | 作用 |
|------|------|
| SSH Tunnel | 端到端加密传输，突破防火墙 |
| Clash | 智能分流，GeoIP 规则 |
| HTTP/SOCKS5 | 代理协议 |
| GeoIP | IP 地理位置识别 |
| systemd | 服务管理 |

### 1.3 优势

- **安全**: SSH 端到端加密，无法被嗅探
- **简单**: 无需额外软件，SSH 原生支持
- **快速**: 直接走 SSH 隧道，低延迟
- **智能**: 国内/海外流量自动分流
- **多用户**: 支持多个独立用户

---

## 2. 环境要求

### 2.1 服务器端

| 要求 | 规格 |
|------|------|
| 系统 | Ubuntu 18.04+ / Debian 10+ / CentOS 7+ |
| CPU | 1 核以上 |
| 内存 | 512MB 以上 |
| 带宽 | 1Mbps 以上 |
| IP | 海外独立 IP |

### 2.2 客户端

| 要求 | 规格 |
|------|------|
| 系统 | Windows / macOS / Linux |
| Clash | 客户端已安装 |
| SSH | OpenSSH 客户端 |

### 2.3 网络需求

- 服务器 SSH 端口 (默认 22) 可访问
- 服务器到海外网络通畅

---

## 3. 服务器部署

### 3.1 第一步：准备服务器

通过 SSH 连接到你的海外服务器：

```bash
ssh root@your-server-ip
```

> **提示**: 将 `your-server-ip` 替换为你的服务器 IP 地址

更新系统软件包：

```bash
# Ubuntu/Debian
apt update && apt upgrade -y

# CentOS
yum update -y
```

### 3.2 第二步：创建工作目录

```bash
mkdir -p /opt/clash-deploy && cd /opt/clash-deploy
```

### 3.3 第三步：下载 Clash

查看服务器架构：

```bash
dpkg --print-architecture
```

常见的架构返回值：
- `amd64` - 64位 x86
- `arm64` - ARM 64位
- `armhf` - ARM 32位

下载对应版本的 Clash：

```bash
# 以 v1.18.0 amd64 为例
CLASH_VERSION="1.18.0"
ARCH=$(dpkg --print-architecture)

wget -O /tmp/clash.gz \
  "https://github.com/Dreamacro/clash/releases/download/v${CLASH_VERSION}/clash-${CLASH_VERSION}-linux-${ARCH}.gz"

# 解压并安装
gunzip /tmp/clash.gz
mv /tmp/clash /usr/local/bin/clash
chmod +x /usr/local/bin/clash

# 验证安装
clash --version
```

> **注意**: 如果 GitHub 下载慢，可以使用镜像或其他方式

### 3.4 第四步：创建用户和目录

```bash
# 创建 clash 用户 (非登录用户)
useradd -r -s /usr/sbin/nologin -M clash

# 创建配置和日志目录
mkdir -p /etc/clash /var/log/clash

# 设置权限
chown -R clash:clash /etc/clash /var/log/clash
ls -la /etc/clash/
```

### 3.5 第五步：下载 GeoIP 数据库

GeoIP 数据库用于判断 IP 地理位置，是智能分流的核心：

```bash
curl -L -o /etc/clash/Country.mmdb \
  https://github.com/Dreamacro/max-match-files/raw/refs/heads/main/Country.mmdb

# 设置权限
chown clash:clash /etc/clash/Country.mmdb

# 验证
ls -lh /etc/clash/Country.mmdb
```

### 3.6 第六步：配置 Clash

创建配置文件：

```bash
vi /etc/clash/config.yaml
```

粘贴以下内容（智能分流配置）：

```yaml
# Clash Server Config - 智能分流版

# 代理端口 (供 SSH 隧道连接)
port: 7890
socks-port: 7891

# 仅允许本地连接
allow-lan: false
bind-address: "*"

# 运行模式: rule (规则) / global (全局) / direct (直连)
mode: rule

# 日志级别
log-level: info

# RESTful API (仅本地访问)
external-controller: 127.0.0.1:9090

# DNS 配置 - 智能分流核心
dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  # 国内 DNS
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
    - 114.114.114.114
  # 海外 DNS
  fallback:
    - 8.8.8.8
    - 1.1.1.1
  fallback-filter:
    geoip: true
    geoip-code: CN

# 代理配置
proxies:
  - name: "direct"
    type: direct

# 代理组
proxy-groups:
  - name: "auto"
    type: select
    proxies:
      - direct

# 智能分流规则
rules:
  # ========== GeoIP 地理分流 ==========
  - GEOIP,CN,DIRECT

  # ========== 国内域名直连 ==========
  - DOMAIN-SUFFIX,cn,DIRECT
  - DOMAIN-SUFFIX,baidu.com,DIRECT
  - DOMAIN-SUFFIX,bdstatic.com,DIRECT
  - DOMAIN-SUFFIX,qq.com,DIRECT
  - DOMAIN-SUFFIX,tencent.com,DIRECT
  - DOMAIN-SUFFIX,weixin.com,DIRECT
  - DOMAIN-SUFFIX,taobao.com,DIRECT
  - DOMAIN-SUFFIX,tmall.com,DIRECT
  - DOMAIN-SUFFIX,alibaba.com,DIRECT
  - DOMAIN-SUFFIX,alipay.com,DIRECT
  - DOMAIN-SUFFIX,aliyun.com,DIRECT
  - DOMAIN-SUFFIX,jd.com,DIRECT
  - DOMAIN-SUFFIX,163.com,DIRECT
  - DOMAIN-SUFFIX,126.com,DIRECT
  - DOMAIN-SUFFIX,netease.com,DIRECT
  - DOMAIN-SUFFIX,youku.com,DIRECT
  - DOMAIN-SUFFIX,iqiyi.com,DIRECT
  - DOMAIN-SUFFIX,bilibili.com,DIRECT
  - DOMAIN-SUFFIX,douban.com,DIRECT
  - DOMAIN-SUFFIX,zhihu.com,DIRECT
  - DOMAIN-SUFFIX,sina.com,DIRECT
  - DOMAIN-SUFFIX,weibo.com,DIRECT
  - DOMAIN-SUFFIX,sohu.com,DIRECT
  - DOMAIN-SUFFIX,gov.cn,DIRECT
  - DOMAIN-SUFFIX,edu.cn,DIRECT
  - DOMAIN-SUFFIX,csdn.net,DIRECT
  - DOMAIN-SUFFIX,steamcommunity.com,DIRECT
  - DOMAIN-SUFFIX,icbc.com,DIRECT
  - DOMAIN-SUFFIX,icloud.com,DIRECT
  - DOMAIN-SUFFIX,apple.com,DIRECT

  # ========== 默认规则 ==========
  - MATCH,auto
```

> **提示**: 按 `i` 进入编辑模式，粘贴后按 `Esc` 退出，再输入 `:wq` 保存

设置配置文件权限：

```bash
chown clash:clash /etc/clash/config.yaml
chmod 640 /etc/clash/config.yaml
```

### 3.7 第七步：配置 systemd 服务

创建服务文件：

```bash
vi /etc/systemd/system/clash.service
```

粘贴以下内容：

```ini
[Unit]
Description=Clash Proxy Service
Documentation=https://github.com/Dreamacro/clash
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=clash
Group=clash
ExecStart=/usr/local/bin/clash -d /etc/clash -f /etc/clash/config.yaml
Restart=on-failure
RestartSec=5

# 日志
StandardOutput=journal
StandardError=journal
SyslogIdentifier=clash

# 安全加固
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/log/clash

[Install]
WantedBy=multi-user.target
```

重新加载 systemd：

```bash
systemctl daemon-reload
```

### 3.8 第八步：启动 Clash 服务

```bash
# 启动服务
systemctl start clash

# 设置开机自启
systemctl enable clash

# 检查服务状态
systemctl status clash
```

正常状态输出：
```
● clash.service - Clash Proxy Service
   Loaded: loaded (/etc/systemd/system/clash.service; enabled)
   Active: active (running) since ...
 Main PID: xxxx (clash)
```

### 3.9 第九步：测试 Clash 服务

在服务器本地测试：

```bash
# 测试 HTTP 代理
curl -x http://127.0.0.1:7890 https://www.google.com

# 测试 SOCKS5 代理
curl -x socks5://127.0.0.1:7891 https://www.google.com

# 查看 Clash 日志
journalctl -u clash -f --no-pager
```

### 3.10 第十步：配置防火墙

使用 UFW 防火墙（Ubuntu/Debian）：

```bash
# 安装 UFW
apt install -y ufw

# 设置默认策略
ufw default deny incoming
ufw default allow outgoing

# 允许 SSH
ufw allow ssh
# 或指定端口
ufw allow 22/tcp

# 启用防火墙
ufw --force enable

# 查看状态
ufw status verbose
```

### 3.11 第十一步：创建代理用户

创建专门用于 SSH 隧道的用户：

```bash
# 创建用户
PROXY_USER="proxyuser"
useradd -m -s /usr/sbin/nologin $PROXY_USER

# 创建 SSH 目录
mkdir -p /home/$PROXY_USER/.ssh
chmod 700 /home/$PROXY_USER/.ssh

# 创建授权文件
touch /home/$PROXY_USER/.ssh/authorized_keys
chmod 600 /home/$PROXY_USER/.ssh/authorized_keys
chown -R $PROXY_USER:$PROXY_USER /home/$PROXY_USER/.ssh

echo "用户 $PROXY_USER 创建完成"
```

### 3.12 第十二步：配置 SSH 安全

编辑 SSH 配置：

```bash
vi /etc/ssh/sshd_config
```

确保以下配置：

```ssh-config
Port 22
Protocol 2
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
AllowTcpForwarding yes
GatewayPorts no
MaxAuthTries 3
ClientAliveInterval 60
ClientAliveCountMax 3
```

添加允许的用户：

```ssh-config
AllowUsers proxyuser
```

重启 SSH 服务：

```bash
# 先不要断开当前连接！
# 在新终端测试新配置后再重启

# 测试配置语法
sshd -t

# 重启 SSH
systemctl restart sshd
```

---

## 4. 客户端配置

### 4.1 Windows 系统

#### 4.1.1 安装 Clash for Windows

1. 下载 [Clash for Windows](https://github.com/Fndroid/clash_for_windows_pkg/releases)
2. 解压并运行
3. 界面语言可切换为中文

#### 4.1.2 配置 SSH 隧道

**方法一：使用 PowerShell**

```powershell
# 建立 SSH 隧道
ssh -N -f -L 7890:127.0.0.1:7890 proxyuser@your-server-ip -p 22

# 查看隧道是否运行
Get-NetTCPConnection -LocalPort 7890
```

**方法二：使用 PuTTY**

1. 打开 PuTTY
2. Connection > SSH > Tunnels
3. Source port: `7890`
4. Destination: `127.0.0.1:7890`
5. 点击 Add
6. 返回 Session，填写 Host Name 和端口
7. 点击 Open

#### 4.1.3 配置 Clash 客户端

1. 打开 Clash for Windows
2. 进入「配置」页面
3. 编辑 `config.yaml`，或直接导入配置

**客户端配置示例** (`%APPDATA%\Clash\config.yaml`)：

```yaml
# Clash Client Config

# 本地代理端口
port: 7890
socks-port: 7891
allow-lan: false
bind-address: "*"

# 运行模式
mode: rule
log-level: info

# RESTful API
external-controller: 127.0.0.1:9090

# DNS 配置
dns:
  enable: true
  listen: 127.0.0.1:53
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
  fallback:
    - 8.8.8.8
    - 1.1.1.1

# 远程服务器代理 (通过 SSH 隧道)
proxies:
  - name: "ssh-tunnel"
    type: http
    server: 127.0.0.1
    port: 7890

# 代理组
proxy-groups:
  - name: "auto"
    type: select
    proxies:
      - ssh-tunnel

# 智能分流规则
rules:
  - GEOIP,CN,DIRECT
  - DOMAIN-SUFFIX,cn,DIRECT
  - DOMAIN-SUFFIX,baidu.com,DIRECT
  - DOMAIN-SUFFIX,qq.com,DIRECT
  - DOMAIN-SUFFIX,taobao.com,DIRECT
  - DOMAIN-SUFFIX,jd.com,DIRECT
  - DOMAIN-SUFFIX,alibaba.com,DIRECT
  - DOMAIN-SUFFIX,tencent.com,DIRECT
  - DOMAIN-SUFFIX,weixin.com,DIRECT
  - DOMAIN-SUFFIX,bilibili.com,DIRECT
  - DOMAIN-SUFFIX,zhihu.com,DIRECT
  - MATCH,auto
```

4. 点击「服务模式」启用
5. 系统代理选择 `auto` 或 `ssh-tunnel`

### 4.2 macOS 系统

#### 4.2.1 安装 ClashX

1. 下载 [ClashX](https://github.com/yichengchen/clashX/releases) 或 [ClashX Pro](https://install.istio.cn/download/clashX/darwin)
2. 安装到应用程序

#### 4.2.2 配置 SSH 隧道

打开终端：

```bash
# 建立 SSH 隧道
ssh -N -f -L 7890:127.0.0.1:7890 proxyuser@your-server-ip -p 22

# 保持连接 (可选)
# 添加 -o ServerAliveInterval=60
```

#### 4.2.3 配置 Clash

1. 打开 ClashX
2. 点击顶部菜单 > 配置 > 高级设置
3. 编辑配置文件，导入上述客户端配置

### 4.3 Linux 系统

#### 4.3.1 安装 Clash

```bash
# 下载
wget -O /tmp/clash.gz \
  "https://github.com/Dreamacro/clash/releases/download/v1.18.0/clash-1.18.0-linux-amd64.gz"

gunzip /tmp/clash.gz
sudo mv /tmp/clash /usr/local/bin/clash
sudo chmod +x /usr/local/bin/clash
```

#### 4.3.2 配置 SSH 隧道

```bash
# 建立隧道
ssh -N -f -L 7890:127.0.0.1:7890 proxyuser@your-server-ip -p 22

# 查看进程
ps aux | grep ssh

# 断开隧道
pkill -f "ssh.*-L.*7890"
```

#### 4.3.3 配置 Clash

```bash
mkdir -p ~/.config/clash
vi ~/.config/clash/config.yaml
# 粘贴客户端配置
```

启动 Clash：

```bash
clash -d ~/.config/clash -f ~/.config/clash/config.yaml
```

或使用 systemd 用户服务：

```bash
mkdir -p ~/.config/systemd/user
vi ~/.config/systemd/user/clash.service
```

---

## 5. 连接使用

### 5.1 建立连接流程

```
┌─────────────────────────────────────────────────────────────┐
│                        完整连接步骤                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. [本地] 建立 SSH 隧道                                     │
│     $ ssh -N -f -L 7890:127.0.0.1:7890 proxyuser@server     │
│                                                              │
│  2. [本地] 启动 Clash 客户端                                 │
│     - 确保系统代理已启用                                      │
│     - 选择代理组为 ssh-tunnel                                │
│                                                              │
│  3. [本地] 验证连接                                          │
│     $ curl -x http://127.0.0.1:7890 https://www.google.com  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 SSH 隧道连接脚本

创建便捷脚本 `connect.sh`：

```bash
#!/bin/bash
# SSH Tunnel + Clash 连接脚本

REMOTE_USER="proxyuser"
REMOTE_HOST="your-server-ip"
REMOTE_PORT="22"
LOCAL_PORT="7890"

echo "正在连接 $REMOTE_USER@$REMOTE_HOST..."

ssh -N -f \
  -o StrictHostKeyChecking=no \
  -o ServerAliveInterval=60 \
  -o ServerAliveCountMax=3 \
  -L "$LOCAL_PORT:127.0.0.1:7890" \
  -p "$REMOTE_PORT" \
  "$REMOTE_USER@$REMOTE_HOST"

if [ $? -eq 0 ]; then
    echo "SSH 隧道已建立 -> 127.0.0.1:$LOCAL_PORT"
    echo "现在可以启动 Clash 客户端"
else
    echo "连接失败"
fi
```

使用：

```bash
chmod +x connect.sh
./connect.sh
```

### 5.3 断开连接

```bash
# 断开 SSH 隧道
pkill -f "ssh.*-L.*7890"

# 或使用脚本
./disconnect.sh
```

### 5.4 验证测试

#### 测试 1：检查隧道

```bash
# Windows
netstat -ano | findstr "7890"

# Linux/macOS
netstat -tlnp | grep 7890
```

#### 测试 2：代理连通性

```bash
# 通过代理访问 Google
curl -x http://127.0.0.1:7890 https://www.google.com

# 通过 SOCKS5 代理
curl -x socks5://127.0.0.1:7891 https://www.google.com
```

#### 测试 3：检查出口 IP

```bash
# 查看代理后的 IP
curl -x http://127.0.0.1:7890 https://api.ipify.org

# 应该显示服务器 IP，而不是本地 IP
```

#### 测试 4：DNS 泄露检测

访问以下网站检查是否有 DNS 泄露：
- https://ipleak.net
- https://dnsleaktest.com

#### 测试 5：分流验证

```bash
# 国内网站 - 应该直连，快速响应
curl -x http://127.0.0.1:7890 https://www.baidu.com -w "\nTime: %{time_total}s\n"

# 海外网站 - 通过代理
curl -x http://127.0.0.1:7890 https://www.google.com -w "\nTime: %{time_total}s\n"
```

---

## 6. 多用户配置

### 6.1 多用户架构

```
                    ┌──────────────────────────────┐
                    │        海外服务器             │
                    │                              │
  用户 A ──SSH──┐   │  ┌─────────┐  ┌─────────┐   │
               │   │  │Clash A │  │Clash B │   │
  用户 B ──SSH──┼───┼──│Port 7890│  │Port 7891│   │
               │   │  └─────────┘  └─────────┘   │
  用户 C ──SSH──┘   │                              │
                    └──────────────────────────────┘
```

### 6.2 创建多用户

```bash
# 用户 A
useradd -m -s /usr/sbin/nologin user_a
mkdir -p /etc/clash/user_a
mkdir -p /home/user_a/.ssh
touch /home/user_a/.ssh/authorized_keys
chmod 700 /home/user_a/.ssh
chmod 600 /home/user_a/.ssh/authorized_keys
chown -R user_a:user_a /home/user_a/.ssh

# 用户 B
useradd -m -s /usr/sbin/nologin user_b
mkdir -p /etc/clash/user_b
mkdir -p /home/user_b/.ssh
touch /home/user_b/.ssh/authorized_keys
chmod 700 /home/user_b/.ssh
chmod 600 /home/user_b/.ssh/authorized_keys
chown -R user_b:user_b /home/user_b/.ssh

# Clash 配置
cp /etc/clash/config.yaml /etc/clash/user_a/config.yaml
cp /etc/clash/config.yaml /etc/clash/user_b/config.yaml

# 修改端口
# user_a: port: 7890
# user_b: port: 7891
```

### 6.3 启动多个 Clash 实例

```bash
# 启动用户 A 的 Clash
su - clash -s /bin/bash -c "/usr/local/bin/clash -d /etc/clash/user_a -f /etc/clash/user_a/config.yaml &"

# 启动用户 B 的 Clash
su - clash -s /bin/bash -c "/usr/local/bin/clash -d /etc/clash/user_b -f /etc/clash/user_b/config.yaml &"

# 创建 systemd 实例服务
ln -s /etc/systemd/system/clash.service /etc/systemd/system/clash@.service
systemctl enable clash@user_a
systemctl start clash@user_a
```

### 6.4 多用户 SSH 隧道

用户 A 连接：
```bash
ssh -N -f -L 7890:127.0.0.1:7890 user_a@server
```

用户 B 连接：
```bash
ssh -N -f -L 7891:127.0.0.1:7891 user_b@server
```

---

## 7. 安全加固

### 7.1 SSH 安全

#### 7.1.1 禁用密码登录

```bash
# 编辑 /etc/ssh/sshd_config
PasswordAuthentication no
PubkeyAuthentication yes
```

#### 7.1.2 使用强密钥

```bash
# 生成 ED25519 密钥 (推荐)
ssh-keygen -t ed25519 -C "your_email@example.com"

# 或 RSA 4096
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

#### 7.1.3 上传公钥

```bash
# 本地执行
ssh-copy-id -i ~/.ssh/id_ed25519.pub proxyuser@server-ip

# 手动上传
cat ~/.ssh/id_ed25519.pub | ssh proxyuser@server-ip "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

#### 7.1.4 修改 SSH 端口

```bash
# 编辑 /etc/ssh/sshd_config
Port 2222  # 改为非标准端口
```

### 7.2 Fail2ban 防暴力破解

```bash
# 安装
apt install -y fail2ban

# 配置
vi /etc/fail2ban/jail.local
```

配置内容：

```ini
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
```

启动：

```bash
systemctl enable fail2ban
systemctl start fail2ban
```

### 7.3 系统安全

#### 7.3.1 自动安全更新

```bash
apt install -y unattended-upgrades
dpkg-reconfigure unattended-upgrades
```

#### 7.3.2 禁用不必要的服务

```bash
systemctl stop bluetooth
systemctl disable bluetooth
systemctl mask cups
```

#### 7.3.3 内核参数优化

编辑 `/etc/sysctl.conf`：

```bash
# IP 欺骗防护
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 禁用 ICMP 重定向
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# 启用 SYN Cookie
net.ipv4.tcp_syncookies = 1

# 日志 Martian 包
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
```

应用：

```bash
sysctl -p
```

### 7.4 Clash 安全

#### 7.4.1 限制端口访问

Clash 只监听本地：

```yaml
allow-lan: false
bind-address: "127.0.0.1"
```

#### 7.4.2 API 访问控制

```yaml
external-controller: 127.0.0.1:9090
```

不要绑定到 `0.0.0.0`

---

## 8. 故障排除

### 8.1 常见问题

#### 问题 1：SSH 隧道连接失败

```
ssh: connect to host server-ip port 22: Connection refused
```

**解决**：
1. 检查服务器 SSH 是否运行：`systemctl status sshd`
2. 检查端口是否正确：`22` 或你修改后的端口
3. 检查防火墙：`ufw status`
4. 检查服务器 IP 是否正确

#### 问题 2：Clash 服务启动失败

```
Failed to start clash.service
```

**解决**：
1. 检查配置语法：`clash -t -d /etc/clash -f /etc/clash/config.yaml`
2. 检查日志：`journalctl -u clash --no-pager -n 50`
3. 检查端口占用：`netstat -tlnp | grep 7890`
4. 检查 GeoIP 数据库：`ls -lh /etc/clash/Country.mmdb`

#### 问题 3：代理无响应

**解决**：
1. 检查 SSH 隧道：`ps aux | grep ssh`
2. 检查本地端口：`netstat -tlnp | grep 7890`
3. 测试服务器 Clash：`curl -x http://127.0.0.1:7890 https://www.google.com`
4. 检查客户端配置是否正确指向 `127.0.0.1:7890`

#### 问题 4：国内网站走代理（应该直连）

**解决**：
1. 检查 GeoIP 数据库是否存在
2. 检查规则是否有误
3. 更新 GeoIP 数据库
4. 确认 Clash 运行模式是 `rule`

#### 问题 5：DNS 泄露

**解决**：
1. 确保客户端使用 fake-ip 模式
2. 配置系统 DNS 为 127.0.0.1
3. 检查 fallback-filter 配置

### 8.2 诊断命令

```bash
# 服务器端
journalctl -u clash -f --no-pager          # 查看 Clash 日志
ss -tlnp | grep clash                      # 检查端口
curl -x http://127.0.0.1:7890 https://www.google.com  # 测试代理

# 客户端
ps aux | grep ssh                          # 检查 SSH 隧道
netstat -tlnp | grep 7890                  # 检查本地端口
curl -x http://127.0.0.1:7890 https://www.google.com  # 测试代理
```

---

## 9. 日常维护

### 9.1 更新 Clash

```bash
# 停止服务
systemctl stop clash

# 下载新版本
cd /tmp
CLASH_VERSION="1.18.0"
wget -O clash.gz "https://github.com/Dreamacro/clash/releases/download/v${CLASH_VERSION}/clash-${CLASH_VERSION}-linux-amd64.gz"

# 备份旧版本
cp /usr/local/bin/clash /usr/local/bin/clash.bak

# 安装新版本
gunzip clash.gz
mv clash /usr/local/bin/clash
chmod +x /usr/local/bin/clash

# 重启服务
systemctl start clash
```

### 9.2 更新 GeoIP 数据库

```bash
# 下载新数据库
curl -L -o /etc/clash/Country.mmdb \
  https://github.com/Dreamacro/max-match-files/raw/refs/heads/main/Country.mmdb

# 重启 Clash
systemctl restart clash
```

### 9.3 查看使用统计

通过 RESTful API：

```bash
# 查看代理组
curl http://127.0.0.1:9090/proxies

# 查看配置
curl http://127.0.0.1:9090/configs

# 查看连接
curl http://127.0.0.1:9090/connections
```

### 9.4 备份配置

```bash
# 备份 Clash 配置
tar -czvf clash-backup-$(date +%Y%m%d).tar.gz \
  /etc/clash \
  /etc/ssh/sshd_config \
  /etc/systemd/system/clash.service
```

### 9.5 日志管理

```bash
# 查看最近日志
journalctl -u clash --no-pager -n 100

# 清理旧日志 (如果日志文件过大)
truncate -s 0 /var/log/clash/*.log

# 配置日志轮转
vi /etc/logrotate.d/clash
```

---

## 附录

### A. 快速命令参考

| 操作 | 命令 |
|------|------|
| 启动 Clash | `systemctl start clash` |
| 停止 Clash | `systemctl stop clash` |
| 重启 Clash | `systemctl restart clash` |
| 查看状态 | `systemctl status clash` |
| 查看日志 | `journalctl -u clash -f` |
| 测试配置 | `clash -t -d /etc/clash -f /etc/clash/config.yaml` |
| 建立隧道 | `ssh -N -f -L 7890:127.0.0.1:7890 proxyuser@server` |
| 断开隧道 | `pkill -f "ssh.*-L.*7890"` |

### B. 端口说明

| 端口 | 用途 | 访问 |
|------|------|------|
| 22 | SSH | 服务器外部 |
| 7890 | HTTP 代理 | SSH 隧道内 |
| 7891 | SOCKS5 代理 | SSH 隧道内 |
| 9090 | Clash API | 仅本地 |

### C. 文件路径

| 文件 | 用途 |
|------|------|
| `/usr/local/bin/clash` | Clash 主程序 |
| `/etc/clash/config.yaml` | Clash 配置 |
| `/etc/clash/Country.mmdb` | GeoIP 数据库 |
| `/etc/systemd/system/clash.service` | systemd 服务 |
| `/var/log/clash/` | Clash 日志目录 |

---

**文档版本**: 1.0
**更新日期**: 2026-04-07
