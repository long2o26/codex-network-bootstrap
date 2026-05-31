#!/usr/bin/env bash
set -euo pipefail

NODE_NAME=""
SERVER_IP=""
ADMIN_USER="codexops"
SSH_PUBLIC_KEY=""
XRAY_PORT="443"
HY2_PORT="8443"
REALITY_SERVER_NAME="www.microsoft.com"
REALITY_DEST="www.microsoft.com:443"
MASQUERADE_URL="https://www.microsoft.com/"
ENABLE_UFW="1"
LOCKDOWN_SSH="1"

usage() {
  cat <<'EOF'
Usage:
  sudo bash setup-node.sh --node-name tokyo --server-ip 1.2.3.4 --ssh-public-key "ssh-ed25519 ..."

Options:
  --node-name NAME              Logical node name, for example tokyo or singapore. Required.
  --server-ip IP                Public IPv4 shown in client config. Optional but recommended.
  --admin-user USER             Non-root sudo user to create. Default: codexops.
  --ssh-public-key KEY          Public SSH key for the admin user.
  --xray-port PORT              VLESS REALITY TCP port. Default: 443.
  --hy2-port PORT               Hysteria2 UDP port. Default: 8443.
  --reality-server-name NAME    REALITY serverName/SNI. Default: www.microsoft.com.
  --reality-dest HOST:PORT      REALITY dest. Default: www.microsoft.com:443.
  --masquerade-url URL          Hysteria2 masquerade URL. Default: https://www.microsoft.com/.
  --no-ufw                      Do not configure UFW.
  --no-ssh-lockdown             Do not disable SSH password login.
  -h, --help                    Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node-name) NODE_NAME="$2"; shift 2 ;;
    --server-ip) SERVER_IP="$2"; shift 2 ;;
    --admin-user) ADMIN_USER="$2"; shift 2 ;;
    --ssh-public-key) SSH_PUBLIC_KEY="$2"; shift 2 ;;
    --xray-port) XRAY_PORT="$2"; shift 2 ;;
    --hy2-port) HY2_PORT="$2"; shift 2 ;;
    --reality-server-name) REALITY_SERVER_NAME="$2"; shift 2 ;;
    --reality-dest) REALITY_DEST="$2"; shift 2 ;;
    --masquerade-url) MASQUERADE_URL="$2"; shift 2 ;;
    --no-ufw) ENABLE_UFW="0"; shift ;;
    --no-ssh-lockdown) LOCKDOWN_SSH="0"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$NODE_NAME" ]]; then
  echo "--node-name is required" >&2
  exit 1
fi

if [[ "$(id -u)" != "0" ]]; then
  echo "Run this script with sudo/root." >&2
  exit 1
fi

if ! grep -qiE 'ubuntu|debian' /etc/os-release; then
  echo "This script targets Ubuntu/Debian servers." >&2
  exit 1
fi

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y curl ca-certificates jq openssl sudo ufw
}

create_admin_user() {
  if ! id "$ADMIN_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$ADMIN_USER"
  fi
  usermod -aG sudo "$ADMIN_USER"
  mkdir -p "/home/$ADMIN_USER/.ssh"
  chmod 700 "/home/$ADMIN_USER/.ssh"
  if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    grep -qxF "$SSH_PUBLIC_KEY" "/home/$ADMIN_USER/.ssh/authorized_keys" 2>/dev/null || \
      echo "$SSH_PUBLIC_KEY" >> "/home/$ADMIN_USER/.ssh/authorized_keys"
  fi
  chmod 600 "/home/$ADMIN_USER/.ssh/authorized_keys" 2>/dev/null || true
  chown -R "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.ssh"
  echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$ADMIN_USER"
  chmod 440 "/etc/sudoers.d/90-$ADMIN_USER"
}

harden_ssh() {
  if [[ "$LOCKDOWN_SSH" != "1" ]]; then
    return
  fi
  if [[ -z "$SSH_PUBLIC_KEY" ]]; then
    echo "Skipping SSH lockdown because --ssh-public-key was not provided."
    return
  fi
  cat > /etc/ssh/sshd_config.d/99-codex-node.conf <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
EOF
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
}

install_xray() {
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

install_hysteria2() {
  bash <(curl -fsSL https://get.hy2.sh/)
}

write_xray_config() {
  local uuid private_key public_key short_id
  uuid="$(xray uuid)"
  private_key="$(xray x25519 | awk -F': ' '/Private key/ {print $2}')"
  public_key="$(xray x25519 -i "$private_key" | awk -F': ' '/Public key/ {print $2}')"
  short_id="$(openssl rand -hex 8)"

  install -d -m 755 /usr/local/etc/xray
  cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "listen": "0.0.0.0",
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "flow": "xtls-rprx-vision",
            "email": "$NODE_NAME@codex-node"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$REALITY_DEST",
          "xver": 0,
          "serverNames": [
            "$REALITY_SERVER_NAME"
          ],
          "privateKey": "$private_key",
          "shortIds": [
            "$short_id"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ]
}
EOF

  install -d -m 700 /etc/codex-node
  jq -n \
    --arg node_name "$NODE_NAME" \
    --arg server_ip "$SERVER_IP" \
    --arg uuid "$uuid" \
    --arg public_key "$public_key" \
    --arg short_id "$short_id" \
    --arg server_name "$REALITY_SERVER_NAME" \
    --argjson port "$XRAY_PORT" \
    '{
      node_name: $node_name,
      server_ip: $server_ip,
      vless: {
        port: $port,
        uuid: $uuid,
        flow: "xtls-rprx-vision",
        server_name: $server_name,
        public_key: $public_key,
        short_id: $short_id
      }
    }' > /etc/codex-node/summary.json

  chmod 600 /etc/codex-node/summary.json
  systemctl enable --now xray
  systemctl restart xray
}

write_hysteria2_config() {
  local password cert key
  password="$(openssl rand -base64 32 | tr -d '\n')"
  cert="/etc/hysteria/selfsigned.crt"
  key="/etc/hysteria/selfsigned.key"

  install -d -m 755 /etc/hysteria
  openssl req -x509 -nodes -newkey ec \
    -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$key" \
    -out "$cert" \
    -subj "/CN=$NODE_NAME.codex-node.local" \
    -days 3650
  chmod 600 "$key"

  cat > /etc/hysteria/config.yaml <<EOF
listen: :$HY2_PORT

tls:
  cert: $cert
  key: $key

auth:
  type: password
  password: "$password"

masquerade:
  type: proxy
  proxy:
    url: $MASQUERADE_URL
    rewriteHost: true
EOF

  jq \
    --arg password "$password" \
    --arg sni "$NODE_NAME.codex-node.local" \
    --argjson port "$HY2_PORT" \
    '. + {hysteria2: {port: $port, password: $password, sni: $sni, skip_cert_verify: true}}' \
    /etc/codex-node/summary.json > /etc/codex-node/summary.tmp
  mv /etc/codex-node/summary.tmp /etc/codex-node/summary.json
  chmod 600 /etc/codex-node/summary.json

  systemctl enable --now hysteria-server.service
  systemctl restart hysteria-server.service
}

configure_firewall() {
  if [[ "$ENABLE_UFW" != "1" ]]; then
    return
  fi
  ufw allow OpenSSH
  ufw allow "$XRAY_PORT/tcp"
  ufw allow "$HY2_PORT/udp"
  ufw --force enable
}

main() {
  install_packages
  create_admin_user
  harden_ssh
  install_xray
  install_hysteria2
  write_xray_config
  write_hysteria2_config
  configure_firewall
  echo
  echo "Node installed. Save this JSON locally:"
  cat /etc/codex-node/summary.json
}

main "$@"
