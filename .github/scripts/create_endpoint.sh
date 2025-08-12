#!/bin/bash

set -e

echo "🔧 Setting defaults"
az configure --defaults workspace="$aml_workspace" group="$resource_group"

echo "🔍 Checking if endpoint exists..."
endpoint_status=$(az ml online-endpoint show \
  --name "$endpoint_name" \
  --query "provisioning_state" \
  -o tsv 2>/dev/null || true)

echo "ℹ️ Endpoint provisioning state: ${endpoint_status:-<not found>}"

if [ "$endpoint_status" == "Succeeded" ]; then
  echo "✅ Endpoint $endpoint_name already exists and is in 'Succeeded' state"
elif [ -n "$endpoint_status" ]; then
    echo "⚠️ Endpoint exists but is not in 'Succeeded' state. Deleting it."
    az ml online-endpoint delete --name "$endpoint_name" --yes
    echo "🚀 Re-creating"
    az ml online-endpoint create -f $endpoint_config --name "$endpoint_name"
fi

