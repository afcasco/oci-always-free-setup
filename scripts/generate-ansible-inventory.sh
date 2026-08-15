#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-production}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform/oci"
VARS_FILE="$ROOT/ansible/inventory/group_vars/all/vars.yml"

PUBLIC_IP="$(terraform -chdir="$TF_DIR" output -raw instance_public_ip)"
PRIVATE_IP="$(terraform -chdir="$TF_DIR" output -raw instance_private_ip)"

readarray -t VALUES < <(
python3 - <<PY
import yaml
with open("$VARS_FILE") as f:
    data = yaml.safe_load(f)

print(data["bootstrap_user"])
print(data["admin_user"])
print(data["server_hostname"])
print(data["wireguard_server_address"])
PY
)

BOOTSTRAP_USER="${VALUES[0]}"
ADMIN_USER="${VALUES[1]}"
SERVER_HOSTNAME="${VALUES[2]}"
WIREGUARD_SERVER_ADDRESS="${VALUES[3]}"
WIREGUARD_SERVER_IP="${WIREGUARD_SERVER_ADDRESS%%/*}"

case "$MODE" in
  bootstrap)
    OUT="$ROOT/ansible/inventory/bootstrap.yml"
    SSH_USER="$BOOTSTRAP_USER"
    SSH_HOST="$PUBLIC_IP"
    ANSIBLE_GROUP="bootstrap"
    ;;

  production-bootstrap)
    OUT="$ROOT/ansible/inventory/production.yml"
    SSH_USER="$ADMIN_USER"
    SSH_HOST="$PUBLIC_IP"
    ANSIBLE_GROUP="production"
    ;;

  production)
    OUT="$ROOT/ansible/inventory/production.yml"
    SSH_USER="$ADMIN_USER"
    SSH_HOST="$WIREGUARD_SERVER_IP"
    ANSIBLE_GROUP="production"
    ;;

  *)
    echo "Usage: $0 [bootstrap|production-bootstrap|production]"
    exit 1
    ;;
esac

cat > "$OUT" <<EOF
all:
  children:
    ${ANSIBLE_GROUP}:
      hosts:
        ${SERVER_HOSTNAME}:
          ansible_host: ${SSH_HOST}
          ansible_user: ${SSH_USER}
          caddy_bind_ip: ${PRIVATE_IP}
EOF

echo "Generated $OUT using SSH user '$SSH_USER' and host '$SSH_HOST'"