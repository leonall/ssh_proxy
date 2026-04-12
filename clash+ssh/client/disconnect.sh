#!/bin/bash
# 断开 SSH 隧道

LOCAL_PORT="${1:-7890}"

echo "正在断开 SSH 隧道 (端口: $LOCAL_PORT)..."

# 查找并杀死进程
pkill -f "ssh.*-L.*$LOCAL_PORT"

if [ $? -eq 0 ]; then
    echo "SSH 隧道已断开"
else
    echo "未找到运行中的 SSH 隧道"
fi
