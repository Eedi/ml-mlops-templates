#!/bin/bash

set -e

echo "🔧 Setting defaults"
az configure --defaults workspace="$aml_workspace" group="$resource_group"

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
