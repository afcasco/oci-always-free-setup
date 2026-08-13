#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_DIR="$ROOT/terraform/bootstrap-state"
OUT="$ROOT/terraform/oci/backend.hcl"

BUCKET="$(terraform -chdir="$BOOTSTRAP_DIR" output -raw state_bucket_name)"
NAMESPACE="$(terraform -chdir="$BOOTSTRAP_DIR" output -raw object_storage_namespace)"
REGION="$(terraform -chdir="$BOOTSTRAP_DIR" output -raw region)"

cat > "$OUT" <<EOF
bucket    = "$BUCKET"
namespace = "$NAMESPACE"
key       = "oci/terraform.tfstate"
region    = "$REGION"
EOF

echo "Generated $OUT"