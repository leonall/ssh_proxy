#!/usr/bin/env python3

import json
import shutil
import subprocess
import sys
from pathlib import Path


CONFIG_PATH = Path("/etc/sing-box/config.json")
SERVICE_NAME = "sing-box"


def run(cmd):
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except FileNotFoundError:
        return 127, "", f"command not found: {cmd[0]}"


def print_result(ok, title, detail=""):
    status = "OK" if ok else "FAIL"
    print(f"[{status}] {title}")
    if detail:
        print(detail)


def load_config():
    if not CONFIG_PATH.exists():
        print_result(False, f"config missing: {CONFIG_PATH}")
        return None

    try:
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except Exception as exc:
        print_result(False, f"config parse failed: {CONFIG_PATH}", str(exc))
        return None


def check_service():
    code, out, err = run(["systemctl", "is-active", SERVICE_NAME])
    ok = code == 0 and out == "active"
    detail = out or err
    print_result(ok, f"systemd service: {SERVICE_NAME}", detail)
    return ok


def check_listener(port):
    code, out, err = run(["ss", "-lunp"])
    if code != 0:
        print_result(False, "udp listener check failed", err or out)
        return False

    lines = [line for line in out.splitlines() if f":{port}" in line]
    ok = len(lines) > 0
    detail = "\n".join(lines[:5])
    print_result(ok, f"udp listen on port {port}", detail or "no matching udp listener")
    return ok


def check_cert(path_str, label):
    path = Path(path_str)
    ok = path.exists()
    detail = str(path)
    print_result(ok, f"{label} exists", detail)
    return ok


def check_ufw(port):
    if not shutil.which("ufw"):
        print_result(True, "ufw not installed", "skip firewall check")
        return True

    code, out, err = run(["ufw", "status"])
    if code != 0:
        print_result(False, "ufw status failed", err or out)
        return False

    wanted = [f"{port}/udp", f"{port}/tcp"]
    matched = [line for line in out.splitlines() if any(item in line for item in wanted)]
    ok = len(matched) > 0
    detail = "\n".join(matched[:10]) or "no matching ufw rules"
    print_result(ok, f"ufw has rule for port {port}", detail)
    return ok


def main():
    print("sing-box server check")
    print(f"config: {CONFIG_PATH}")
    print("")

    config = load_config()
    if not config:
        sys.exit(1)

    inbound = None
    for item in config.get("inbounds", []):
        if item.get("type") == "hysteria2":
            inbound = item
            break

    if not inbound:
        print_result(False, "hysteria2 inbound missing")
        sys.exit(1)

    port = inbound.get("listen_port")
    tls_cfg = inbound.get("tls", {})

    print_result(True, "hysteria2 inbound found", f"listen_port={port}")
    check_service()
    check_listener(port)
    check_cert(tls_cfg.get("certificate_path", ""), "certificate")
    check_cert(tls_cfg.get("key_path", ""), "private key")
    check_ufw(port)

    print("")
    print("extra commands")
    print("systemctl status sing-box --no-pager")
    print("journalctl -u sing-box -n 50 --no-pager")
    print(f"ss -lunp | grep {port}")


if __name__ == "__main__":
    main()
