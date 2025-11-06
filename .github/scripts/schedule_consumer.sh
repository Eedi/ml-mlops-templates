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
QUEUE_NAME="${6:-q-${endpoint_lower}-${TRAFFIC}}"
CONTAINER="${7:-blob-${Q}}"
SCHED="${8:-qc-${endpoint_lower}-${TRAFFIC}}"
CRON="${consumer_cron:-0 * * * *}"
MAX_MSG="${consumer_max_messages:-8000}"
JOB_YAML="./mlops/azureml/configs/queue_consumer_job.yml"
TIMEZONE="UTC" 
endpoint_lower="$(echo "${ENDPOINT}" | tr '[:upper:]' '[:lower:]')"
echo "🔔 Scheduling consumer:"
echo "  RG/WS        : ${RG}/${WS}"
echo "  schedule     : ${SCHED}"
echo "  job yaml     : ${JOB_YAML}"
echo "  queue        : ${QUEUE_NAME}"
echo "  container    : ${CONTAINER}"
echo "  cron         : ${CRON}"
echo "  max_messages : ${MAX_MSG}"
echo "  storage acct : ${STORAGE}"
echo "  timezone     : ${TIMEZONE}"
tmp_sched="$(mktemp)"
cat > "${tmp_sched}" <<YAML
$schema: https://azuremlschemas.azureedge.net/latest/schedule.schema.json
name: ${SCHED}
display_name: ${SCHED}
trigger:
  type: cron
  expression: "${CRON}"
  time_zone: "${TIMEZONE}"
create_job: ${JOB_YAML}
YAML
az extension show -n ml >/dev/null 2>&1 || az extension add -n ml -y >/dev/null
if az ml schedule show -g "${RG}" -w "${WS}" -n "${SCHED}" >/dev/null 2>&1; then
  echo "↻ Updating existing schedule ${SCHED}"
  az ml schedule update -g "${RG}" -w "${WS}" -f "${tmp_sched}"     --set inputs.queue_name="${QUEUE_NAME}"           inputs.parquet_container="${CONTAINER}"           inputs.max_messages="${MAX_MSG}"           inputs.storage_account_name="${STORAGE}" >/dev/null
else
  echo "➕ Creating schedule ${SCHED}"
  az ml schedule create -g "${RG}" -w "${WS}" -f "${tmp_sched}"     --set inputs.queue_name="${QUEUE_NAME}"           inputs.parquet_container="${CONTAINER}"           inputs.max_messages="${MAX_MSG}"           inputs.storage_account_name="${STORAGE}" >/dev/null
fi
rm -f "${tmp_sched}" || true
echo "✅ Schedule ensured: ${SCHED}"
