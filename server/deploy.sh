#!/bin/bash
# Clash Server 一键部署脚本
# 在海外服务器上运行此脚本

set -e

# ========== 配置 ==========
CLASH_VERSION="1.18.0"
PROXY_USER="proxyuser"
SSH_PORT="22"

# ========== 颜色输出 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

# ========== 检查 Root ==========
if [ "$EUID" -ne 0 ]; then
    log_err "请使用 root 用户运行此脚本"
    exit 1
fi

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Clash Server 一键部署脚本${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# ========== 1. 系统更新 ==========
log_info "更新系统软件包..."
apt update && apt upgrade -y
log_ok "系统更新完成"

# ========== 2. 安装基础依赖 ==========
log_info "安装基础依赖..."
apt install -y curl wget ufw fail2ban systemd
log_ok "基础依赖安装完成"

# ========== 3. 下载 Clash ==========
log_info "下载 Clash v${CLASH_VERSION}..."

ARCH=$(dpkg --print-architecture)
CLASH_URL="https://github.com/Dreamacro/clash/releases/download/v${CLASH_VERSION}/clash-${CLASH_VERSION}-linux-${ARCH}.gz"

if wget -O /tmp/clash.gz "$CLASH_URL" 2>/dev/null; then
    gunzip -f /tmp/clash.gz
    mv /tmp/clash /usr/local/bin/clash
    chmod +x /usr/local/bin/clash
    log_ok "Clash 下载并安装完成 (架构: $ARCH)"
else
    log_err "Clash 下载失败，请检查架构支持或网络连接"
    exit 1
fi

# ========== 4. 创建 Clash 用户和目录 ==========
log_info "创建 Clash 用户和目录..."

id -u clash &>/dev/null || useradd -r -s /usr/sbin/nologin -M clash

mkdir -p /etc/clash /var/log/clash
chown -R clash:clash /etc/clash /var/log/clash

log_ok "用户和目录创建完成"

# ========== 5. 下载 GeoIP 数据库 ==========
log_info "下载 GeoIP 数据库..."
if [ -f /etc/clash/Country.mmdb ]; then
    log_warn "GeoIP 数据库已存在，跳过下载"
else
    curl -L -o /etc/clash/Country.mmdb \
        https://github.com/Dreamacro/max-match-files/raw/refs/heads/main/Country.mmdb
    chown clash:clash /etc/clash/Country.mmdb
    log_ok "GeoIP 数据库下载完成"
fi

# ========== 6. 配置 Clash ==========
log_info "配置 Clash 服务..."

# 复制配置文件
if [ -f ./config.yaml ]; then
    cp ./config.yaml /etc/clash/config.yaml
    chown clash:clash /etc/clash/config.yaml
    log_ok "Clash 配置文件已复制"
else
    log_warn "未找到 config.yaml，使用默认配置"
fi

# ========== 7. 安装 systemd 服务 ==========
log_info "安装 systemd 服务..."

if [ -f ./clash.service ]; then
    cp ./clash.service /etc/systemd/system/clash.service
else
    # 直接创建服务文件
    cat > /etc/systemd/system/clash.service << 'EOF'
[Unit]
Description=Clash Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=clash
Group=clash
ExecStart=/usr/local/bin/clash -d /etc/clash -f /etc/clash/config.yaml
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl daemon-reload
systemctl enable clash
systemctl start clash

if systemctl is-active --quiet clash; then
    log_ok "Clash 服务已启动"
else
    log_err "Clash 服务启动失败"
    journalctl -u clash --no-pager
    exit 1
fi

# ========== 8. 配置防火墙 ==========
log_info "配置防火墙 (UFW)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw --force enable
log_ok "防火墙配置完成"

# ========== 9. 创建代理用户 ==========
log_info "创建代理用户: $PROXY_USER..."

if id "$PROXY_USER" &>/dev/null; then
    log_warn "用户 $PROXY_USER 已存在"
else
    useradd -m -s /usr/sbin/nologin "$PROXY_USER"
    mkdir -p /home/$PROXY_USER/.ssh
    chmod 700 /home/$PROXY_USER/.ssh
    touch /home/$PROXY_USER/.ssh/authorized_keys
    chmod 600 /home/$PROXY_USER/.ssh/authorized_keys
    chown -R $PROXY_USER:$PROXY_USER /home/$PROXY_USER/.ssh
    log_ok "用户 $PROXY_USER 创建完成"
fi

echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  部署完成！${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "${GREEN}下一步操作:${NC}"
echo ""
echo "1. 上传 SSH 公钥到服务器:"
echo "   ssh-copy-id -i ~/.ssh/id_ed25519.pub $PROXY_USER@$(hostname -I | awk '{print $1}')"
echo ""
echo "2. 编辑 SSH 配置 (可选):"
echo "   # 添加以下内容到 /etc/ssh/sshd_config"
echo "   AllowUsers $PROXY_USER"
echo "   PasswordAuthentication no"
echo "   然后重启 SSH: systemctl restart sshd"
echo ""
echo "3. 测试 Clash 服务:"
echo "   curl -x http://127.0.0.1:7890 https://www.google.com"
echo ""
echo "4. 查看 Clash 状态:"
echo "   systemctl status clash"
echo "   journalctl -u clash -f"
echo ""
