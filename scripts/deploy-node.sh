#!/usr/bin/env bash
set -euo pipefail

HOST=""
NODE_NAME=""
SERVER_IP=""
SSH_PUBLIC_KEY_FILE="${HOME}/.ssh/id_ed25519.pub"
SSH_PORT="22"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/deploy-node.sh --host ubuntu@1.2.3.4 --node-name tokyo --server-ip 1.2.3.4

Options:
  --host USER@IP              SSH target. Required.
  --node-name NAME            Logical node name: tokyo or singapore. Required.
  --server-ip IP              Public IP for client config. Defaults to IP part of --host.
  --ssh-public-key-file PATH  Public key to install on server. Default: ~/.ssh/id_ed25519.pub.
  --ssh-port PORT             SSH port. Default: 22.
  -h, --help                  Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --node-name) NODE_NAME="$2"; shift 2 ;;
    --server-ip) SERVER_IP="$2"; shift 2 ;;
    --ssh-public-key-file) SSH_PUBLIC_KEY_FILE="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$HOST" || -z "$NODE_NAME" ]]; then
  usage >&2
  exit 1
fi

if [[ -z "$SERVER_IP" ]]; then
  SERVER_IP="${HOST##*@}"
fi

if [[ ! -f "$SSH_PUBLIC_KEY_FILE" ]]; then
  echo "Public key file not found: $SSH_PUBLIC_KEY_FILE" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLIC_KEY="$(cat "$SSH_PUBLIC_KEY_FILE")"
mkdir -p "$ROOT_DIR/secrets"

quote_arg() {
  printf "%q" "$1"
}

scp -P "$SSH_PORT" "$ROOT_DIR/server/setup-node.sh" "$HOST:/tmp/codex-setup-node.sh"
ssh -p "$SSH_PORT" "$HOST" "sudo bash /tmp/codex-setup-node.sh --node-name $(quote_arg "$NODE_NAME") --server-ip $(quote_arg "$SERVER_IP") --ssh-public-key $(quote_arg "$PUBLIC_KEY")"
ssh -p "$SSH_PORT" "$HOST" "sudo cat /etc/codex-node/summary.json" > "$ROOT_DIR/secrets/$NODE_NAME.json"

echo "Saved node summary to $ROOT_DIR/secrets/$NODE_NAME.json"
