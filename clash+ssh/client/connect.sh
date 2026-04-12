#!/bin/bash
# SSH Tunnel + Clash 连接脚本
# 用法: ./connect.sh [用户名] [服务器地址] [SSH端口]

# 配置 (根据实际情况修改)
REMOTE_USER="${1:-proxyuser}"
REMOTE_HOST="${2:-your-server-ip}"
REMOTE_PORT="${3:-22}"
LOCAL_PORT="7890"
REMOTE_CLASH_PORT="7890"
KEY_FILE="$HOME/.ssh/id_ed25519"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}SSH Tunnel + Clash 连接脚本${NC}"
echo "----------------------------------------"
echo "服务器: $REMOTE_HOST:$REMOTE_PORT"
echo "用户: $REMOTE_USER"
echo "本地端口: $LOCAL_PORT -> 远程:127.0.0.1:$REMOTE_CLASH_PORT"
echo "----------------------------------------"

# 检查 SSH 密钥是否存在
if [ ! -f "$KEY_FILE" ]; then
    echo -e "${YELLOW}SSH 密钥不存在，正在生成...${NC}"
    ssh-keygen -t ed25519 -C "clash-tunnel@$(hostname)" -f "$KEY_FILE" -N ""
    echo -e "${GREEN}密钥已生成: $KEY_FILE${NC}"
    echo -e "${YELLOW}请先上传公钥到服务器:${NC}"
    echo "ssh-copy-id -i $KEY_FILE.pub $REMOTE_USER@$REMOTE_HOST"
    exit 1
fi

# 检查是否已有 SSH 隧道在运行
EXISTING=$(ps aux | grep "ssh.*-L.*$LOCAL_PORT" | grep -v grep)
if [ -n "$EXISTING" ]; then
    echo -e "${YELLOW}发现已有 SSH 隧道运行中:${NC}"
    echo "$EXISTING"
    echo -e "${YELLOW}正在重启...${NC}"
    pkill -f "ssh.*-L.*$LOCAL_PORT.*$REMOTE_HOST"
    sleep 1
fi

# 建立 SSH 隧道
echo -e "${GREEN}正在建立 SSH 隧道...${NC}"
ssh -N -f \
    -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -o ConnectTimeout=10 \
    -o UserKnownHostsFile=/dev/null \
    -i "$KEY_FILE" \
    -L "$LOCAL_PORT:127.0.0.1:$REMOTE_CLASH_PORT" \
    -p "$REMOTE_PORT" \
    "$REMOTE_USER@$REMOTE_HOST"

# 检查连接状态
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[成功] SSH 隧道已建立${NC}"
    echo -e "${GREEN}本地代理地址: 127.0.0.1:$LOCAL_PORT${NC}"
    echo ""
    echo -e "${YELLOW}Clash 配置提示:${NC}"
    echo "请确保 Clash 客户端配置为:"
    echo "  proxies:"
    echo "    - name: ssh-tunnel"
    echo "      type: http"
    echo "      server: 127.0.0.1"
    echo "      port: $LOCAL_PORT"
    echo ""
    echo -e "${YELLOW}测试命令:${NC}"
    echo "curl --socks5 127.0.0.1:7891 https://www.google.com"
else
    echo -e "${RED}[失败] SSH 隧道建立失败${NC}"
    exit 1
fi

# 保持后台运行提示
echo ""
echo -e "${YELLOW}提示:${NC}"
echo "- 查看隧道进程: ps aux | grep 'ssh.*-L'"
echo "- 断开隧道: pkill -f 'ssh.*-L.*$LOCAL_PORT'"
echo "- 重新连接: $0 $REMOTE_USER $REMOTE_HOST $REMOTE_PORT"
