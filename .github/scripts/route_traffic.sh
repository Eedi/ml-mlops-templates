#!/bin/bash

set -e

is_set() {
    local val="$1"
    [[ -n "$val" && "$val" -ne 0 ]]
}

echo "🔧 Setting defaults"
az configure --defaults workspace="$aml_workspace" group="$resource_group"


if ! is_set "$green_deployment_name" && ! is_set "$blue_deployment_name"; then
    echo "Error: At least one deployment name must be defined."
    exit 1
fi

traffic_config=""

if is_set "$green_deployment_name"; then
    traffic_config="${green_deployment_name}=${green_traffic_percentage}"
    if is_set "$green_mirror_percentage"; then
        mirror_traffic_config="${green_deployment_name}=${green_mirror_percentage}"
    fi
fi

if is_set "$blue_deployment_name"; then
    traffic_config="${blue_deployment_name}=${blue_traffic_percentage} ${traffic_config}"
    if is_set "$blue_mirror_percentage"; then
        mirror_traffic_config="${blue_deployment_name}=${blue_mirror_percentage}"
    fi
fi

# Remove leading/trailing whitespace
traffic_config="$(echo "$traffic_config" | xargs)"
mirror_traffic_config="$(echo "$mirror_traffic_config" | xargs)"



echo "🔍 Checking if endpoint exists..."
endpoint_status=$(az ml online-endpoint show \
  --name "$endpoint_name" \
  --query "provisioning_state" \
  -o tsv 2>/dev/null || true)

echo "ℹ️ Endpoint provisioning state: ${endpoint_status:-<not found>}"

if [ "$endpoint_status" == "Succeeded" ]; then
  echo "✅ Updating existing endpoint: $endpoint_name"
  update_args=(-f "$endpoint_config" --name "$endpoint_name" --traffic "$traffic_config")
  [ -n "$mirror_traffic_config" ] && update_args+=(--mirror-traffic "$mirror_traffic_config")
  az ml online-endpoint update "${update_args[@]}"
else
  echo "❌ Endpoint $endpoint_name is not in 'Succeeded' state. Failing."
  exit 1
fi

