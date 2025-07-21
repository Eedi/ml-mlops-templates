#!/bin/bash

# =============================================================================
# Setup Azure Monitor alerts for Azure ML endpoints
#
# This script sets up monitoring alerts for Azure ML endpoints.
# It creates/updates an action group with Slack webhook integration and configures
# two types of alerts:
# 1. Application Insights metric alert for HTTP 4xx/5xx errors
# 2. Log Analytics query alert for non-200 response codes
#
# Required environment variables:
#   - slack_webhook_url: URL for Slack webhook notifications
#   - resource_group: Azure resource group name
#   - endpoint_name: Name of the Azure ML endpoint
#   - envname: Environment name (dev/prod)
#   - aml_workspace: Azure ML workspace name
#
# Optional environment variables (with defaults):
#   - severity: Alert severity (0=Critical, 1=Error, 2=Warning, 3=Informational)
#   - check_frequency: How often to check (default: 5m)
#   - window_size: Time window for evaluation (default: 15m)
#   - error_threshold: Number of errors to trigger alert (default: 10)
# =============================================================================

# Exit on any error
set -e

# Enable error handling
trap 'echo "❌ Error occurred at line $LINENO. Command: $BASH_COMMAND"' ERR

# Prevent Git Bash from converting paths on Windows
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

# =============================================================================
# Validate required environment variables
# =============================================================================
required_vars=("resource_group" "endpoint_name" "envname" "aml_workspace" "action_group_name")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "::error::Required environment variable '$var' is not set"
        exit 1
    fi
done

# =============================================================================
# Set default values for optional variables
# =============================================================================
severity="${severity:-1}"
check_frequency="${check_frequency:-5m}"
window_size="${window_size:-15m}"
error_threshold="${error_threshold:-10}"

# =============================================================================
# Configure Azure defaults
# =============================================================================
echo "🔧 Setting Azure defaults"
az configure --defaults workspace="$aml_workspace" group="$resource_group"



# =============================================================================
# Get the action group ID
# =============================================================================
echo "🔑 Getting action group ID..."
action_group_id=$(az monitor action-group show \
    --name "$action_group_name" \
    --resource-group $resource_group \
    --query id -o tsv)

if [ -z "$action_group_id" ]; then
    echo "::error::Failed to get action group ID"
    echo "   - Action Group Name: $action_group_name"
    echo "   - Resource Group: $resource_group"
    exit 1
fi

echo "ℹ️ Action Group ID: $action_group_id"


# =============================================================================
# Get the endpoint ID
# =============================================================================
endpoint_id=$(az ml online-endpoint show -n $endpoint_name --query "id" -o tsv)

# =============================================================================
# Create or update Log Analytics query alert rule
# =============================================================================
echo "🚀 Creating Log Analytics query alert rule: Non-200 response codes"

log_alert_name="${endpoint_name}-non-200-alert"

# Delete existing alert if it exists
echo "🔍 Checking if Log Analytics alert rule exists..."
log_alert_status=$(az monitor scheduled-query show \
    --name "$log_alert_name" \
    --resource-group $resource_group \
    --query "name" \
    -o tsv 2>/dev/null || true)

echo "ℹ️ Log Analytics alert rule status: ${log_alert_status:-<not found>}"

if [ -n "$log_alert_status" ]; then
    echo "🗑️  Deleting existing Log Analytics alert rule: $log_alert_name"
    echo "   - Resource Group: $resource_group"
    echo "   - Alert Name: $log_alert_name"
    
    delete_log_result=$(az monitor scheduled-query delete \
        --name "$log_alert_name" \
        --resource-group $resource_group \
        --yes 2>&1)
    delete_exit_code=$?
    
    if [ $delete_exit_code -eq 0 ]; then
        echo "✅ Successfully deleted existing Log Analytics alert rule"
    elif [[ "$delete_log_result" == *"not found"* ]] || [[ "$delete_log_result" == *"NotFound"* ]]; then
        echo "ℹ️  Log Analytics alert rule not found (already deleted or never existed)"
    else
        echo "⚠️  Warning: Failed to delete existing Log Analytics alert rule"
        echo "   - Error: $delete_log_result"
        echo "   - Exit Code: $delete_exit_code"
        echo "   - Continuing with creation..."
    fi
else
    echo "ℹ️  No existing Log Analytics alert rule found, proceeding with creation"
fi

echo "🚀 Creating Log Analytics query alert rule: $log_alert_name"


# Create the Log Analytics alert for non-200 Azure ML endpoint traffic
az monitor scheduled-query create \
    --name "$log_alert_name" \
    --resource-group $resource_group \
    --scopes "$endpoint_id" \
    --description "Alert on non-200 HTTP status codes from Azure ML endpoints (Endpoint: $endpoint_name)" \
    --severity $severity \
    --evaluation-frequency $check_frequency \
    --window-size $window_size \
    --condition-query "Non200ResponseCount=AmlOnlineEndpointTrafficLog | where ResponseCode != \"200\" | summarize Count = count()" \
    --condition "total \"Non200ResponseCount\" > 5" \
    --action-groups $action_group_id \
    --custom-properties "CustomKey1=$endpoint_name" \
    --tags "team=data-science" "repo=ml-azua" "environment=$envname" \
    --verbose


echo "✅ Alert setup complete!"
