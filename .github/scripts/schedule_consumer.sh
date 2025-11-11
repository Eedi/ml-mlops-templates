#!/usr/bin/env bash
# schedule_consumer.sh
# Usage:
#   schedule_consumer.sh <resource_group> <workspace> <endpoint_name> <traffic_type> <storage_account> [queue_name] [container] [schedule_name]
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
# UAMI_RESOURCE_ID="${9:?uami resource id required}"
# UAMI_CLIENT_ID="${10:?uami client id required}"

CRON="${consumer_cron:-0 * * * *}"
MAX_MSG="${consumer_max_messages:-8000}"
TIMEZONE="${TIMEZONE:-UTC}"

PIPELINE_YAML="${PIPELINE_YAML:-$(realpath mlops/azureml/configs/queue_consumer_pipeline.yml)}"

echo "🔔 Scheduling consumer:"
echo "  RG/WS        : ${RG}/${WS}"
echo "  schedule     : ${SCHED}"
echo "  queue        : ${QUEUE_NAME}"
echo "  container    : ${CONTAINER}"
echo "  cron         : ${CRON}"
echo "  max_messages : ${MAX_MSG}"
echo "  storage acct : ${STORAGE}"
echo "  pipeline     : ${PIPELINE_YAML}"

test -f "${PIPELINE_YAML}" || { echo "❌ pipeline YAML not found: ${PIPELINE_YAML}"; exit 1; }

tmp_sched="$(mktemp --suffix .yml)"
cleanup(){ rm -f "${tmp_sched}"; }
trap cleanup EXIT

yq -i "
  .inputs.storage_account_name = \"${STORAGE}\" |
  .inputs.queue_name = \"${QUEUE_NAME}\" |
  .inputs.parquet_container = \"${CONTAINER}\" |
  .inputs.max_messages = ${MAX_MSG}
" "${PIPELINE_YAML}"
  # .jobs.consumer.identity.type = \"user_assigned\" |
  # .jobs.consumer.identity.user_assigned_identities = [{\"resource_id\": \"${UAMI_RESOURCE_ID}\"}] |  
  # .jobs.consumer.environment_variables.AZURE_CLIENT_ID = \"${UAMI_CLIENT_ID}\"
cat > "${tmp_sched}" <<YAML
\$schema: https://azuremlschemas.azureedge.net/latest/schedule.schema.json
name: ${SCHED}
display_name: ${SCHED}
trigger:
  type: cron
  expression: "${CRON}"
  time_zone: "${TIMEZONE}"
create_job: "$(realpath "${PIPELINE_YAML}")"
YAML

az ml schedule create -g "${RG}" -w "${WS}" -f "${tmp_sched}"

echo "✅ Schedule ensured: ${SCHED}"
