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
required_vars=("slack_webhook_url" "resource_group" "endpoint_name" "envname" "aml_workspace")
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
echo "🔧 Setting Azure defaults for resource group: $resource_group"
az configure --defaults group="$resource_group"

# =============================================================================
# Create or update action group
# =============================================================================
echo "🔍 Checking if action group exists..."
action_group_name="ag-slack-$resource_group"
action_group_status=$(az monitor action-group show \
    --name "$action_group_name" \
    --resource-group $resource_group \
    --query "name" \
    -o tsv 2>/dev/null || true)

echo "ℹ️ Action group status: ${action_group_status:-<not found>}"

if [ -n "$action_group_status" ]; then
    echo "🔄 Updating existing action group: $action_group_name"
    echo "🗑️  Deleting existing action group..."
    
    delete_result=$(az monitor action-group delete \
        --name "$action_group_name" \
        --resource-group $resource_group 2>&1 || true)
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully deleted existing action group"
    else
        echo "⚠️  Warning: Failed to delete existing action group"
        echo "   - Error: $delete_result"
        echo "   - Continuing with creation..."
    fi
    
    echo "🚀 Creating new action group: $action_group_name"
else
    echo "🚀 Creating action group: $action_group_name"
fi

az monitor action-group create \
    --name "$action_group_name" \
    --resource-group $resource_group \
    --short-name "slack" \
    --action webhook "slack-webhook" "$slack_webhook_url" usecommonalertschema \
    --tags "team=data-science" "repo=ml-azua" "environment=$envname"

# Wait a moment for the action group to be fully created
sleep 2

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
# Get the Application Insights ID
# =============================================================================
echo "🔍 Getting Application Insights ID..."
subscription_id=$(az account show --query id -o tsv)
if [ -z "$subscription_id" ]; then
    echo "::error::Failed to get subscription ID"
    exit 1
fi

app_insights_id="/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.Insights/components/$app_insights_name"
echo "ℹ️ Using Application Insights: $app_insights_name"

# =============================================================================
# Get the Azure ML workspace ID
# =============================================================================
echo "🔍 Getting Azure ML workspace ID..."
# Get workspace ID using Azure CLI to avoid path conversion issues
aml_workspace_id=$(az ml workspace show --name "$aml_workspace" --resource-group "$resource_group" --query id -o tsv)
if [ -z "$aml_workspace_id" ]; then
    echo "::error::Failed to get Azure ML workspace ID"
    exit 1
fi
echo "ℹ️ Using Azure ML workspace: $aml_workspace"
echo "ℹ️ Workspace ID: $aml_workspace_id"


# =============================================================================
# Create or update Log Analytics query alert rule
# =============================================================================
echo "🚀 Creating Log Analytics query alert rule: Non-200 response codes"

log_alert_name="non-200-response-codes-alert"

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
echo "ℹ️ Log Analytics alert configuration details:"
echo "   - Alert Name: $log_alert_name"
echo "   - Resource Group: $resource_group"
echo "   - AML Workspace: $aml_workspace (ID: $aml_workspace_id)"
echo "   - Query: AmlOnlineEndpointTrafficLog | where ResponseCode != \"200\""
echo "   - Condition: count 'Count' > 5"
echo "   - Check frequency: $check_frequency"
echo "   - Window size: $window_size"
echo "   - Severity: $severity"
echo "   - Action Group: $action_group_name"

echo "📋 Creating Log Analytics alert with the following parameters:"
echo "   - Scope: $aml_workspace_id"
echo "   - Query: AmlOnlineEndpointTrafficLog filtered for non-200 responses"
echo "   - Action Group ID: $action_group_id"
echo "   - Action Group Name: $action_group_name"

# Create the Log Analytics alert for non-200 Azure ML endpoint traffic
az monitor scheduled-query create \
    --name "$log_alert_name" \
    --resource-group $resource_group \
    --scopes "$aml_workspace_id" \
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
