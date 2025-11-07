#!/usr/bin/env bash
# Azure ML schedule for the queue consumer
# Usage:
#   schedule_consumer.sh <resource_group> <workspace> <endpoint_name> <traffic_type> <storage_account>
# Env (optional):
#   consumer_cron="*/5 * * * *"
#   consumer_max_messages="8000"
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
JOB_YAML="${JOB_YAML:-/mnt/c/Repo/ML-bis/ml-azua/mlops/azureml/configs/queue_consumer_job.yml}"
TIMEZONE="${TIMEZONE:-UTC}"

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

tmp_job="$(mktemp --suffix .yml)"
tmp_sched="$(mktemp --suffix .yml)"
cleanup(){ rm -f "${tmp_sched}" "${tmp_job}"; }
trap cleanup EXIT

JOB_DIR="$(realpath "$(dirname "$JOB_YAML")")"
REPO_ROOT="$(realpath "${JOB_DIR}/../../..")"
CONDA_ABS="${REPO_ROOT}/mlops/azureml/configs/env-conda.yml"
CODE_ABS="${REPO_ROOT}"

cp "${JOB_YAML}" "${tmp_job}"

yq -i "
  .inputs.queue_name = \"${QUEUE_NAME}\" |
  .inputs.parquet_container = \"${CONTAINER}\" |
  .inputs.storage_account_name = \"${STORAGE}\" |
  .inputs.max_messages = ${MAX_MSG} |
  .compute = \"azureml:cpu-cluster\" |
  .code = \"${CODE_ABS}\" |
  .environment.conda_file = \"${CONDA_ABS}\"
" "${tmp_job}"

cat > "${tmp_sched}" <<YAML
\$schema: https://azuremlschemas.azureedge.net/latest/schedule.schema.json
name: ${SCHED}
display_name: ${SCHED}
trigger:
  type: cron
  expression: "${CRON}"
  time_zone: "${TIMEZONE}"
create_job: "${tmp_job}"
YAML

# Upsert 
az ml schedule create -g "${RG}" -w "${WS}" -f "${tmp_sched}"

echo "✅ Schedule ensured: ${SCHED}"
