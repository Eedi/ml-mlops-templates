#!/usr/bin/env bash
# Azure ML schedule for the queue consumer
# Usage:
#   schedule_consumer.sh <resource_group> <workspace> <endpoint_name> <traffic_type> <storage_account>
# Env (optional):
#   consumer_cron="*/5 * * * *"     # cron string
#   consumer_max_messages="8000"    # max msgs per run
set -euo pipefail
RG="${1:?resource group required}"
WS="${2:?workspace required}"
ENDPOINT="${3:?endpoint required}"
TRAFFIC="${4:?traffic type required}"
STORAGE="${5:?storage account required}"
endpoint_lower="$(echo "${ENDPOINT}" | tr '[:upper:]' '[:lower:]')"
QUEUE_NAME="${6:-q-${endpoint_lower}-${TRAFFIC}}"
CONTAINER="${7:-blob-${QUEUE_NAME}}"
SCHED="${8:-qc-${endpoint_lower}-${TRAFFIC}}"
CRON="${consumer_cron:-0 * * * *}"
MAX_MSG="${consumer_max_messages:-200}"
JOB_YAML="${JOB_YAML:-$GITHUB_WORKSPACE/mlops/azureml/configs/queue_consumer_pipeline.yml}"
TIMEZONE="UTC" 
echo "🔔 Scheduling consumer:"
echo "  RG/WS        : ${RG}/${WS}"
echo "  schedule     : ${SCHED}"
echo "  queue        : ${QUEUE_NAME}"
echo "  container    : ${CONTAINER}"
echo "  cron         : ${CRON}"
echo "  max_messages : ${MAX_MSG}"
echo "  storage acct : ${STORAGE}"
echo "  timezone     : ${TIMEZONE}"
echo "  job yaml     : ${JOB_YAML}"

test -f "${JOB_YAML}" || { echo "❌ JOB_YAML not found: ${JOB_YAML}"; exit 1; }

tmp_job="$(mktemp).yml"
tmp_sched="$(mktemp)"

JOB_DIR="$(realpath "$(dirname "$JOB_YAML")")"
REPO_ROOT="$(realpath "${JOB_DIR}/../../..")"

cp "$JOB_YAML" "$tmp_job"

yq -i "
  .inputs.storage_account_name = {\"type\":\"string\", \"default\": \"$STORAGE\" } |
  .inputs.queue_name           = {\"type\":\"string\", \"default\": \"$QUEUE_NAME\" } |
  .inputs.parquet_container    = {\"type\":\"string\", \"default\": \"$CONTAINER\" } |
  .inputs.max_messages         = {\"type\":\"integer\", \"default\": $MAX_MSG }
" "$tmp_job"

cat > "$tmp_sched" <<YAML
\$schema: https://azuremlschemas.azureedge.net/latest/schedule.schema.json
name: ${SCHED}
display_name: ${SCHED}
trigger:
  type: cron
  expression: "${CRON}"
  time_zone: "${TIMEZONE}"
create_job: ${tmp_job}
YAML

if az ml schedule show -g "${RG}" -w "${WS}" -n "${SCHED}" >/dev/null 2>&1; then
  echo "↻ Updating existing schedule ${SCHED}"
  az ml schedule update -g "${RG}" -w "${WS}" -f "${tmp_sched}"
else
  echo "➕ Creating schedule ${SCHED}"
  az ml schedule create -g "${RG}" -w "${WS}" -f "${tmp_sched}"
fi

rm -f "${tmp_sched}" "${tmp_job}" || true
echo "✅ Schedule ensured: ${SCHED}"