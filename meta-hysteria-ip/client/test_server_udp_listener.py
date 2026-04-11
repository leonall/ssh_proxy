#!/usr/bin/env python3
"""
UDP 端口监听测试脚本
在服务器上运行，监听 443 端口的 UDP 包

使用方法:
    python test_server_udp_listener.py [端口]
"""

import socket
import sys
import time
import struct

def listen_udp(port: int = 443, timeout: float = 10.0):
    """监听 UDP 端口"""
    print(f"[+] 监听 UDP 端口: {port}")
    print(f"[+] 超时时间: {timeout} 秒")
    print("-" * 50)
    print("等待数据包...\n")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        sock.bind(('0.0.0.0', port))
    except OSError as e:
        print(f"[-] 绑定端口 {port} 失败: {e}")
        return

    sock.settimeout(timeout)

    start_time = time.time()
    packet_count = 0

    try:
        while True:
            try:
                data, addr = sock.recvfrom(4096)
                packet_count += 1
                recv_time = time.time()
                elapsed = recv_time - start_time

                print(f"[{elapsed:6.2f}s] 收到 #{packet_count} from {addr[0]}:{addr[1]}")
                print(f"    大小: {len(data)} bytes")
                print(f"    前64字节 (hex): {data[:64].hex()}")

                # 检查是否是 hysteria2 魔数
                if data[:8] == b'\x55\x48\x59\x32\x43\x4c\x4e\x54':
                    print(f"    [+] 检测到 Hysteria2 协议魔数!")
                elif data[:4] == b'\x55\x48\x59\x32':
                    print(f"    [?] 可能是 Hysteria2 (部分魔数匹配)")
                else:
                    print(f"    [-] 非 Hysteria2 协议")

                print()

            except socket.timeout:
                print(f"\n[-] 超时！{timeout} 秒内未收到任何数据包")
                print(f"    共收到: {packet_count} 个数据包")
                break

    except KeyboardInterrupt:
        print(f"\n\n[+] 用户中断")
        print(f"    共收到: {packet_count} 个数据包")

    sock.close()

    return packet_count

def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 443
    timeout = float(sys.argv[2]) if len(sys.argv) > 2 else 10.0

    print("=" * 50)
    print(" UDP 端口监听测试")
    print("=" * 50)

    count = listen_udp(port, timeout)

    print()
    if count == 0:
        print("结论: 服务器没有收到任何 UDP 数据包")
        print("这说明 UDP 包在网络路径上被丢弃了")
    else:
        print(f"结论: 服务器收到了 {count} 个 UDP 数据包")
        print("网络通道是通的！")

if __name__ == "__main__":
    main()
