#!/bin/bash

set -euo pipefail

INPUT="inventory/targets.csv"
OUTPUT_DIR="config/targets"

NODE_FILE="$OUTPUT_DIR/node_targets.yml"
ORACLE_FILE="$OUTPUT_DIR/oracle_targets.yml"
MSSQL_FILE="$OUTPUT_DIR/mssql_targets.yml"

echo "[INFO] Generating targets from $INPUT"

mkdir -p "$OUTPUT_DIR"

# reset files
echo "" > "$NODE_FILE"
echo "" > "$ORACLE_FILE"
echo "" > "$MSSQL_FILE"

# skip header
tail -n +2 "$INPUT" | while IFS=',' read -r host ip node oracle mssql app tier owner
do
  # NODE
  if [ "$node" = "yes" ]; then
    cat >> "$NODE_FILE" <<EOF
- targets:
    - "$ip:9100"
  labels:
    service: "node"
    environment: "development"
    site: "development"
    team: "dba"
    role: "infrastructure"
    db_type: "none"
    app: "$app"
    tier: "$tier"
    owner: "$owner"

EOF
  fi

  # ORACLE
  if [ "$oracle" = "yes" ]; then
    cat >> "$ORACLE_FILE" <<EOF
- targets:
    - "$ip:9161"
  labels:
    service: "oracle"
    environment: "development"
    site: "development"
    team: "dba"
    role: "database"
    db_type: "oracle"
    app: "$app"
    tier: "$tier"
    owner: "$owner"

EOF
  fi

  # MSSQL
  if [ "$mssql" = "yes" ]; then
    cat >> "$MSSQL_FILE" <<EOF
- targets:
    - "$ip:9399"
  labels:
    service: "mssql"
    environment: "development"
    site: "development"
    team: "dba"
    role: "database"
    db_type: "mssql"
    app: "$app"
    tier: "$tier"
    owner: "$owner"

EOF
  fi

done

echo "[DONE] Targets generated:"
ls -lah "$OUTPUT_DIR"
