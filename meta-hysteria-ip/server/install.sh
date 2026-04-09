#!/usr/bin/env bash

set -euo pipefail

SERVER_IP="${1:-${SERVER_IP:-}}"
HY2_PORT="${HY2_PORT:-443}"
SB_VERSION="${SB_VERSION:-}"
HY2_PASSWORD="${HY2_PASSWORD:-}"
OBFS_PASSWORD="${OBFS_PASSWORD:-}"
INSTALL_DIR="/etc/sing-box"
CERT_DIR="${INSTALL_DIR}/certs"
BIN_PATH="/usr/local/bin/sing-box"
SERVICE_PATH="/etc/systemd/system/sing-box.service"

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
    die "Please run this script as root."
  fi
}

require_ip() {
  [[ -n "${SERVER_IP}" ]] || die "Usage: ./install.sh <public-ip>"
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    *) die "Unsupported architecture: ${arch}" ;;
  esac
}

install_dependencies() {
  if command -v apt-get >/dev/null 2>&1; then
    log "Installing dependencies..."
    if command -v dpkg >/dev/null 2>&1; then
      log "Repairing any interrupted dpkg state first..."
      DEBIAN_FRONTEND=noninteractive dpkg --configure -a
    fi
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      curl \
      wget \
      tar \
      openssl \
      ca-certificates \
      jq \
      ufw
  else
    die "This installer currently supports Debian/Ubuntu only."
  fi
}

resolve_latest_version() {
  if [[ -n "${SB_VERSION}" ]]; then
    echo "${SB_VERSION}"
    return
  fi

  log "Resolving latest sing-box version..."
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

  log "Downloading sing-box v${version} (${arch})..."
  wget -qO "${tmp_dir}/sing-box.tar.gz" "${download_url}"
  tar -xzf "${tmp_dir}/sing-box.tar.gz" -C "${tmp_dir}"

  extracted_dir="${tmp_dir}/${package_name}"
  [[ -f "${extracted_dir}/sing-box" ]] || die "sing-box binary not found."

  install -m 0755 "${extracted_dir}/sing-box" "${BIN_PATH}"
  rm -rf "${tmp_dir}"
}

ensure_secrets() {
  if [[ -z "${HY2_PASSWORD}" ]]; then
    HY2_PASSWORD="$(openssl rand -hex 16)"
  fi

  if [[ -z "${OBFS_PASSWORD}" ]]; then
    OBFS_PASSWORD="$(openssl rand -hex 16)"
  fi
}

generate_cert() {
  mkdir -p "${CERT_DIR}"

  cat > "${CERT_DIR}/openssl-ip.cnf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
x509_extensions = v3_req
distinguished_name = dn

[dn]
CN = ${SERVER_IP}

[v3_req]
subjectAltName = @alt_names
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
IP.1 = ${SERVER_IP}
EOF

  if [[ -f "${CERT_DIR}/cert.pem" && -f "${CERT_DIR}/key.pem" ]]; then
    log "Existing self-signed certificate detected, skipping generation."
    return
  fi

  log "Generating self-signed certificate..."
  openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout "${CERT_DIR}/key.pem" \
    -out "${CERT_DIR}/cert.pem" \
    -config "${CERT_DIR}/openssl-ip.cnf"
}

write_config() {
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
          "name": "self-use",
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
        "alpn": [
          "h3"
        ],
        "certificate_path": "${CERT_DIR}/cert.pem",
        "key_path": "${CERT_DIR}/key.pem"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
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
  cat > /etc/sysctl.d/99-sing-box-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

  sysctl --system >/dev/null
}

configure_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    log "Configuring UFW..."
    ufw allow "${HY2_PORT}/tcp"
    ufw allow "${HY2_PORT}/udp"
  else
    warn "UFW not found. Please allow ${HY2_PORT}/tcp and ${HY2_PORT}/udp manually."
  fi
}

start_service() {
  systemctl daemon-reload
  systemctl enable sing-box
  systemctl restart sing-box
}

print_summary() {
  cat <<EOF

Deployment complete.

Server IP
- ${SERVER_IP}

Client settings
- protocol: hysteria2
- port: ${HY2_PORT}
- password: ${HY2_PASSWORD}
- obfs: salamander
- obfs-password: ${OBFS_PASSWORD}
- sni: ${SERVER_IP}
- skip-cert-verify: true

Files
- config: ${INSTALL_DIR}/config.json
- cert: ${CERT_DIR}/cert.pem
- key: ${CERT_DIR}/key.pem

Checks
- systemctl status sing-box
- journalctl -u sing-box -n 50 --no-pager
EOF
}

main() {
  require_root
  require_ip
  install_dependencies
  install_sing_box
  ensure_secrets
  generate_cert
  write_config
  write_service
  enable_bbr
  configure_firewall
  start_service
  print_summary
}

main "$@"
