#!/usr/bin/env bash
# Usage:
#   schedule_consumer.sh <resource_group> <workspace> <endpoint_name> <traffic_type> <storage_account> [queue_name] [parquet_container] [schedule_name]
# Env (optionnel):
#   consumer_cron="*/5 * * * *"
#   consumer_max_messages="8000"
set -euo pipefail

RESOURCE_GROUP="${1:?resource group required}"
WORKSPACE="${2:?workspace required}"
ENDPOINT_NAME="${3:?endpoint required}"
TRAFFIC_TYPE="${4:?traffic type required}"
STORAGE_ACCOUNT="${5:?storage account required}"

endpoint_lower="$(printf '%s' "$ENDPOINT_NAME" | tr '[:upper:]' '[:lower:]')"
QUEUE_NAME="${6:-q-${endpoint_lower}-${TRAFFIC_TYPE}}"
PARQUET_CONTAINER="${7:-blob-${QUEUE_NAME}}"
SCHEDULE_NAME="${8:-qc-${endpoint_lower}-${TRAFFIC_TYPE}}"

CRON="${consumer_cron:-*0 5 * * *}"
MAX_MSG="${consumer_max_messages:-200}"
JOB_YAML="${JOB_YAML:-/mlops/azureml/configs/queue_consumer_job.yml}"
TIMEZONE="${TIMEZONE:-UTC}"
COMPUTE="${COMPUTE:-azureml:cpu-cluster}"

command -v az >/dev/null 2>&1 || { echo "az not found"; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "yq not found"; exit 1; }
test -f "$JOB_YAML" || { echo "❌ JOB_YAML not found: $JOB_YAML"; exit 1; }

tmp_job="$(mktemp --suffix .yml)"
tmp_sched="$(mktemp --suffix .yml)"
cleanup(){ rm -f "$tmp_job" "$tmp_sched"; }
trap cleanup EXIT

cp "$JOB_YAML" "$tmp_job"
yq -i "
  .compute = \"$COMPUTE\" |
  .inputs.storage_account_name.default = \"$STORAGE_ACCOUNT\" |
  .inputs.queue_name.default = \"$QUEUE_NAME\" |
  .inputs.parquet_container.default = \"$PARQUET_CONTAINER\" |
  .inputs.max_messages.default = ${MAX_MSG}
" "$tmp_job"

cat > "$tmp_sched" <<YAML
\$schema: https://azuremlschemas.azureedge.net/latest/schedule.schema.json
name: $SCHEDULE_NAME
display_name: $SCHEDULE_NAME
description: Consumer for $ENDPOINT_NAME ($TRAFFIC_TYPE)
trigger:
  type: cron
  expression: "$CRON"
  time_zone: "$TIMEZONE"
create_job:
  job:
    file: $tmp_job
YAML

set -x
az ml schedule create -g "$RESOURCE_GROUP" -w "$WORKSPACE" -f "$tmp_sched" \
  --set properties.tags.endpoint="$ENDPOINT_NAME" \
        properties.tags.traffic="$TRAFFIC_TYPE" \
|| az ml schedule update -g "$RESOURCE_GROUP" -w "$WORKSPACE" --name "$SCHEDULE_NAME" -f "$tmp_sched"
set +x

echo "✅ Schedule ensured: $SCHEDULE_NAME"
