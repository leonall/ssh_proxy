#!/usr/bin/env bash

set -euo pipefail

DOMAIN="${1:-${DOMAIN:-}}"
EMAIL="${2:-${EMAIL:-}}"
HY2_PORT="${HY2_PORT:-443}"
SB_VERSION="${SB_VERSION:-}"
HY2_PASSWORD="${HY2_PASSWORD:-}"
OBFS_PASSWORD="${OBFS_PASSWORD:-}"
CERT_DIR="${CERT_DIR:-/etc/letsencrypt/live}"
INSTALL_DIR="/etc/sing-box"
SERVICE_PATH="/etc/systemd/system/sing-box.service"
BIN_PATH="/usr/local/bin/sing-box"

log() {
  printf '[INFO] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

die() {
  printf '[ERROR] %s\n' "$1" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "请使用 root 运行安装脚本。"
  fi
}

require_args() {
  [[ -n "${DOMAIN}" ]] || die "缺少域名。用法: ./install.sh your.domain.com you@example.com"
  [[ -n "${EMAIL}" ]] || die "缺少邮箱。用法: ./install.sh your.domain.com you@example.com"
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    *) die "暂不支持的架构: ${arch}" ;;
  esac
}

install_dependencies() {
  if command -v apt-get >/dev/null 2>&1; then
    log "安装依赖..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      curl \
      wget \
      tar \
      openssl \
      certbot \
      jq
  else
    die "当前脚本只覆盖 Debian/Ubuntu 系。"
  fi
}

resolve_latest_version() {
  if [[ -n "${SB_VERSION}" ]]; then
    echo "${SB_VERSION}"
    return
  fi

  log "查询最新 sing-box 版本..."
  curl -fsSL "https://api.github.com/repos/SagerNet/sing-box/releases/latest" \
    | jq -r '.tag_name' \
    | sed 's/^v//'
}

install_sing_box() {
  local version arch tmp_dir package_name download_url extracted_dir
  version="$(resolve_latest_version)"
  arch="$(detect_arch)"
  tmp_dir="$(mktemp -d)"
  package_name="sing-box-${version}-linux-${arch}"
  download_url="https://github.com/SagerNet/sing-box/releases/download/v${version}/${package_name}.tar.gz"

  log "下载 sing-box v${version} (${arch})..."
  wget -qO "${tmp_dir}/sing-box.tar.gz" "${download_url}"
  tar -xzf "${tmp_dir}/sing-box.tar.gz" -C "${tmp_dir}"

  extracted_dir="${tmp_dir}/${package_name}"
  [[ -f "${extracted_dir}/sing-box" ]] || die "未找到 sing-box 可执行文件。"

  install -m 0755 "${extracted_dir}/sing-box" "${BIN_PATH}"
  rm -rf "${tmp_dir}"

  log "sing-box 已安装到 ${BIN_PATH}"
}

ensure_cert() {
  local live_dir
  live_dir="${CERT_DIR}/${DOMAIN}"

  if [[ -f "${live_dir}/fullchain.pem" && -f "${live_dir}/privkey.pem" ]]; then
    log "检测到现有证书，跳过申请。"
    return
  fi

  log "申请 TLS 证书..."
  certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    -m "${EMAIL}" \
    -d "${DOMAIN}" \
    --keep-until-expiring
}

ensure_secrets() {
  if [[ -z "${HY2_PASSWORD}" ]]; then
    HY2_PASSWORD="$(openssl rand -hex 16)"
  fi

  if [[ -z "${OBFS_PASSWORD}" ]]; then
    OBFS_PASSWORD="$(openssl rand -hex 16)"
  fi
}

write_config() {
  local live_dir
  live_dir="${CERT_DIR}/${DOMAIN}"

  mkdir -p "${INSTALL_DIR}"

  cat > "${INSTALL_DIR}/config.json" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${HY2_PORT},
      "users": [
        {
          "name": "clash-meta",
          "password": "${HY2_PASSWORD}"
        }
      ],
      "obfs": {
        "type": "salamander",
        "password": "${OBFS_PASSWORD}"
      },
      "ignore_client_bandwidth": false,
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "alpn": [
          "h3"
        ],
        "certificate_path": "${live_dir}/fullchain.pem",
        "key_path": "${live_dir}/privkey.pem"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "direct"
      }
    ],
    "final": "direct"
  }
}
EOF
}

write_service() {
  cat > "${SERVICE_PATH}" <<'EOF'
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=5
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

enable_bbr() {
  local sysctl_file
  sysctl_file="/etc/sysctl.d/99-sing-box-bbr.conf"

  cat > "${sysctl_file}" <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

  sysctl --system >/dev/null
}

configure_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    log "配置 UFW..."
    ufw allow 80/tcp
    ufw allow "${HY2_PORT}/tcp"
    ufw allow "${HY2_PORT}/udp"
  else
    warn "未检测到 UFW，请手动放行 80/tcp、${HY2_PORT}/tcp 和 ${HY2_PORT}/udp。"
  fi
}

start_service() {
  systemctl daemon-reload
  systemctl enable sing-box
  systemctl restart sing-box
  systemctl --no-pager --full status sing-box
}

print_summary() {
  cat <<EOF

部署完成。

服务端信息
- 域名: ${DOMAIN}
- 端口: ${HY2_PORT}
- 协议: Hysteria2
- 认证密码: ${HY2_PASSWORD}
- Salamander 混淆密码: ${OBFS_PASSWORD}
- 配置文件: ${INSTALL_DIR}/config.json

下一步
1. 把上面的密码保存好。
2. 用 client/mihomo.yaml.example 生成你的 Clash Meta 配置。
3. 执行以下命令确认服务正常:
   systemctl status sing-box
   journalctl -u sing-box -n 50 --no-pager
EOF
}

main() {
  require_root
  require_args
  install_dependencies
  install_sing_box
  ensure_cert
  ensure_secrets
  write_config
  write_service
  enable_bbr
  configure_firewall
  start_service
  print_summary
}

main "$@"
