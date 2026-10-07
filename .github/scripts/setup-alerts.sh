#!/bin/bash

# =============================================================================
# Setup Azure Monitor alerts for Azure ML endpoints
#
# This script sets up monitoring alerts for Azure ML endpoints.
# It looks up the existing action group (Slack integration) and creates/updates
# three Log Analytics query alert rules:
# 1. Critical (Sev 1): any 503, 502 or 424 (model 500) in 15m
# 2. Capacity (Sev 2): any 429, 408 or 424 (model 504) in 15m
# 3. Non-200 rate (Sev 3): more than 20% non-200 in 2h, with at least 3 requests
#
# Required environment variables:
#   - slack_webhook_url: URL for Slack webhook notifications
#   - resource_group: Azure resource group name
#   - endpoint_name: Name of the Azure ML endpoint
#   - envname: Environment name (dev/prod)
#   - aml_workspace: Azure ML workspace name
#
# Optional environment variables (with defaults):
#   - check_frequency: How often to check (default: 5m)
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
# Get the log analytics workspace ID
# =============================================================================


# =============================================================================
# Create or update Log Analytics query alert rules
# =============================================================================

# Set default values for optional variables
check_frequency="${check_frequency:-5m}"

# Args: name, description, severity, window size, query name, query, condition
create_or_update_alert() {
    local log_alert_name="$1" description="$2" severity="$3" window_size="$4" query_name="$5" query="$6" condition="$7"

    echo "🚀 Creating Log Analytics query alert rule: $log_alert_name"

    # Delete existing alert if it exists
    echo "🔍 Checking if Log Analytics alert rule exists..."
    log_alert_status=$(az monitor scheduled-query show \
        --name "$log_alert_name" \
        --resource-group $resource_group \
        --query "name" \
        -o tsv 2>/dev/null || true)

    echo "ℹ️ Log Analytics alert rule status: ${log_alert_status:-<not found>}"

    if [ -n "$log_alert_status" ]; then
        echo "ℹ️  Log Analytics alert rule already exists, updating it"
        command="az monitor scheduled-query update"
    else
        echo "ℹ️  No existing Log Analytics alert rule found, proceeding with creation"
        endpoint_id=$(az ml online-endpoint show -n $endpoint_name --query "id" -o tsv)
        app_insights_id=$(az ml workspace show --query "application_insights" -o tsv)
        log_analytics_workspace_id=$(az monitor app-insights component show --ids $app_insights_id --query "workspaceResourceId" -o tsv)

        # --scopes can only be set at creation time.
        # The case where the endpoint name changes is not handled here.
        command="az monitor scheduled-query create --scopes "$log_analytics_workspace_id""
    fi

    $command \
        --name "$log_alert_name" \
        --resource-group $resource_group \
        --description "$description" \
        --severity $severity \
        --evaluation-frequency $check_frequency \
        --window-size $window_size \
        --condition-query $query_name="$query" \
        --condition "$condition" \
        --action-groups $action_group_id \
        --custom-properties "CustomKey1=$endpoint_name" \
        --tags "team=data-science" "repo=ml-azua" "environment=$envname" \
        --verbose
}

traffic="AmlOnlineEndpointTrafficLog | where EndpointName == '$endpoint_name'"

create_or_update_alert "${endpoint_name}-critical-alert" \
    "Alert on 503, 502 or 424 (model 500) responses from endpoint $endpoint_name" \
    1 15m CriticalResponses \
    "$traffic | where ResponseCode in ('503', '502') or (ResponseCode == '424' and ModelStatusCode == '500')" \
    "count 'CriticalResponses' > 0"

create_or_update_alert "${endpoint_name}-capacity-alert" \
    "Alert on 429, 408 or 424 (model 504) responses from endpoint $endpoint_name" \
    2 15m CapacityResponses \
    "$traffic | where ResponseCode in ('429', '408') or (ResponseCode == '424' and ModelStatusCode == '504')" \
    "count 'CapacityResponses' > 0"

create_or_update_alert "${endpoint_name}-non-200-alert" \
    "Alert on more than 20% non-200 responses (min 3 requests) from endpoint $endpoint_name" \
    3 2h Non200Rate \
    "$traffic | summarize Total = count(), Non200 = countif(ResponseCode != '200') | where Total >= 3 | extend FailureRate = todouble(Non200) / Total" \
    "max FailureRate from 'Non200Rate' > 0.2"


echo "✅ Alert setup complete!"
