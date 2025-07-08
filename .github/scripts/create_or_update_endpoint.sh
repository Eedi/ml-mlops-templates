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
  echo "✅ Updating existing endpoint: $endpoint_name"
  az ml online-endpoint update -f $endpoint_config --name "$endpoint_name"
else
  if [ -n "$endpoint_status" ]; then
    echo "⚠️ Endpoint exists but is not in 'Succeeded' state. Deleting it."
    az ml online-endpoint delete --name "$endpoint_name" --yes
  fi

  echo "🚀 Creating endpoint: $endpoint_name"
  az ml online-endpoint create -f $endpoint_config --name "$endpoint_name"
fi



# Create or update diagnostic settings for the endpoint
endpoint_id=$(az ml online-endpoint show -n $endpoint_name --query "id" -o tsv)
app_insights_id=$(az ml workspace show --query "application_insights" -o tsv)
log_analytics_workspace_id=$(az monitor app-insights component show --ids $app_insights_id --query "workspaceResourceId" -o tsv)
log_config='[{"category":"AmlOnlineEndpointConsoleLog","enabled":true},{"category":"AmlOnlineEndpointTrafficLog","enabled":true},{"category":"AmlOnlineEndpointEventLog","enabled":true}]'

# Check if diagnostic settings exist
diagnostic_exists=$(az monitor diagnostic-settings list --resource "$endpoint_id" --query "value[?name=='${endpoint_name}-logging'].name" -o tsv)

if [ -z "$diagnostic_exists" ]; then
    echo "Creating diagnostic settings for endpoint: $endpoint_name"
    az monitor diagnostic-settings create --name "${endpoint_name}-logging" --resource "$endpoint_id" --logs "$log_config" --workspace "$log_analytics_workspace_id"
else
    echo "Updating diagnostic settings for endpoint: $endpoint_name"
    az monitor diagnostic-settings update --name "${endpoint_name}-logging" --resource "$endpoint_id" --logs "$log_config" --workspace "$log_analytics_workspace_id"
fi
# </create_or
