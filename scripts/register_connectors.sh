#!/usr/bin/env bash
# Idempotently create/update both connectors (PUT /connectors/<name>/config).
set -euo pipefail
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
VARS='$POSTGRES_USER $POSTGRES_PASSWORD $POSTGRES_DB $S3_BUCKET $AWS_REGION'

until curl -sf "$CONNECT_URL/connectors" >/dev/null; do
  echo "waiting for Kafka Connect..."; sleep 3
done

for name in debezium-postgres s3-sink; do
  echo "registering $name"
  envsubst "$VARS" < "connect/$name.json" \
    | curl -sf -X PUT -H "Content-Type: application/json" \
        --data @- "$CONNECT_URL/connectors/$name/config" >/dev/null
done

sleep 3
for name in debezium-postgres s3-sink; do
  curl -s "$CONNECT_URL/connectors/$name/status"; echo
done
