#!/usr/bin/env python3
"""
Hysteria2 UDP 连通性测试脚本
模拟客户端发送 UDP 包到服务器 443 端口

使用方法:
    python test_udp_connect.py <服务器IP> [端口]
"""

import socket
import struct
import time
import sys
import random
import string

def generate_random_bytes(length):
    """生成随机字节"""
    return bytes(random.randint(0, 255) for _ in range(length))

def build_hysteria2_client_hello(server_ip: str, password: str):
    """
    构建 Hysteria2 客户端 Hello 包
    这是一个简化的包结构，实际 Hysteria2 使用 QUIC 协议
    """
    # Hysteria2 协议魔数
    HYSTERIA2_MAGIC = b'\x55\x48\x59\x32\x43\x4c\x4e\x54'  # "UH2CLNT"

    # 构建简化的 hello 包
    packet = bytearray()

    # 魔数
    packet.extend(HYSTERIA2_MAGIC)

    # 版本 (2)
    packet.extend(b'\x02\x00\x00\x00')

    # 时间戳
    timestamp = struct.pack('<I', int(time.time()))
    packet.extend(timestamp)

    # 随机 ID
    packet.extend(generate_random_bytes(8))

    # 密码长度 + 密码
    password_bytes = password.encode()
    packet.extend(struct.pack('<H', len(password_bytes)))
    packet.extend(password_bytes)

    # 随机填充数据 (让包看起来更真实)
    padding_len = random.randint(32, 128)
    packet.extend(struct.pack('<H', padding_len))
    packet.extend(generate_random_bytes(padding_len))

    return bytes(packet)

def send_udp_probe(target_ip: str, port: int = 443, password: str = "test", count: int = 5):
    """发送 UDP 探测包"""
    print(f"[+] 目标: {target_ip}:{port}")
    print(f"[+] 探测次数: {count}")
    print(f"[+] 密码: {password}")
    print("-" * 50)

    # 创建 UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(5)

    results = []

    for i in range(count):
        try:
            # 构造包
            payload = build_hysteria2_client_hello(target_ip, password)

            print(f"\n[*] 发送探测 #{i+1} ({len(payload)} bytes)...")
            send_time = time.time()

            sock.sendto(payload, (target_ip, port))
            print(f"    发送时间: {send_time:.6f}")

            # 尝试接收响应
            try:
                data, addr = sock.recvfrom(4096)
                recv_time = time.time()
                rtt = (recv_time - send_time) * 1000

                print(f"    [!] 收到响应 from {addr}!")
                print(f"    [!] 响应大小: {len(data)} bytes")
                print(f"    [!] RTT: {rtt:.2f} ms")
                print(f"    [!] 响应内容(hex): {data[:64].hex()}")
                results.append(('success', rtt))
            except socket.timeout:
                print(f"    [-] 超时 (5s 内无响应)")

        except Exception as e:
            print(f"    [-] 发送失败: {e}")
            results.append(('error', str(e)))

        time.sleep(0.5)

    sock.close()

    # 统计
    print("\n" + "=" * 50)
    print("统计结果:")
    success_count = sum(1 for r in results if r[0] == 'success')
    print(f"  成功: {success_count}/{count}")

    if success_count > 0:
        rtts = [r[1] for r in results if r[0] == 'success']
        print(f"  平均 RTT: {sum(rtts)/len(rtts):.2f} ms")
        print(f"  最小 RTT: {min(rtts):.2f} ms")
        print(f"  最大 RTT: {max(rtts):.2f} ms")

        # 尝试解码响应
        print("\n[+] 服务器有响应！可能原因:")
        print("    - 服务端密码不匹配")
        print("    - obfs 密码不匹配")
        print("    - 协议版本不兼容")
        print("    - 服务端配置问题")
    else:
        print("\n[-] 没有任何响应！")
        print("\n可能原因:")
        print("    1. 客户端 ISP 封锁了 UDP 443")
        print("    2. 客户端防火墙阻止了 UDP 出站")
        print("    3. 路由器/NAT 问题")
        print("    4. 云厂商安全组未放行 UDP 443")
        print("    5. 服务器防火墙 (iptables/ufw) 未放行 UDP 443")

    return success_count > 0

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    server_ip = sys.argv[1]
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 443
    password = sys.argv[3] if len(sys.argv) > 3 else "test"

    print("=" * 50)
    print(" Hysteria2 UDP 连通性测试")
    print("=" * 50)

    send_udp_probe(server_ip, port, password, count=5)

if __name__ == "__main__":
    main()
