#!/bin/bash

# =============================================================================
# Setup Azure Monitor alerts for Application Insights
#
# This script sets up monitoring alerts for HTTP 500 errors in Application Insights.
# It creates/updates an action group with Slack webhook integration and configures
# a metric alert rule to monitor failed requests.
#
# Required environment variables:
#   - slack_webhook_url: URL for Slack webhook notifications
#   - app_insights_name: Name of the Application Insights instance
#   - resource_group: Azure resource group name
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

# =============================================================================
# Validate required environment variables
# =============================================================================
required_vars=("slack_webhook_url" "app_insights_name" "resource_group")
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
action_group_status=$(az monitor action-group show \
    --name "slack-webhook-alerts" \
    --resource-group $resource_group \
    --query "name" \
    -o tsv 2>/dev/null || true)

echo "ℹ️ Action group status: ${action_group_status:-<not found>}"

if [ -n "$action_group_status" ]; then
    echo "✅ Updating existing action group: slack-webhook-alerts"
    # First remove the existing webhook
    echo "🗑️  Removing existing webhook..."
    az monitor action-group update \
        --name "slack-webhook-alerts" \
        --resource-group $resource_group \
        --remove-action "slack-webhook" || {
            echo "::warning::Failed to remove existing webhook, continuing..."
        }

    # Then add the new webhook
    echo "➕ Adding new webhook..."
    az monitor action-group update \
        --name "slack-webhook-alerts" \
        --resource-group $resource_group \
        --short-name "slack" \
        --add-action webhook "slack-webhook" "$slack_webhook_url" usecommonalertschema
else
    echo "🚀 Creating action group: slack-webhook-alerts"
    az monitor action-group create \
        --name "slack-webhook-alerts" \
        --resource-group $resource_group \
        --short-name "slack" \
        --action webhook "slack-webhook" "$slack_webhook_url" usecommonalertschema
fi

# =============================================================================
# Get the action group ID
# =============================================================================
echo "🔑 Getting action group ID..."
action_group_id=$(az monitor action-group show \
    --name "slack-webhook-alerts" \
    --resource-group $resource_group \
    --query id -o tsv)

if [ -z "$action_group_id" ]; then
    echo "::error::Failed to get action group ID"
    exit 1
fi

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
# Verify Application Insights resource exists
# =============================================================================
echo "🔍 Verifying Application Insights resource..."
if ! az resource list --name "$app_insights_name" --resource-group "$resource_group" --resource-type "Microsoft.Insights/components" --query "[].name" -o tsv | grep -q "^$app_insights_name$"; then
    echo "::error::Application Insights resource '$app_insights_name' not found in resource group '$resource_group'"
    exit 1
fi

# =============================================================================
# Create or update alert rule
# =============================================================================
echo "🔍 Checking if alert rule exists..."
alert_status=$(az monitor metrics alert show \
    --name "http-500-errors-alert" \
    --resource-group $resource_group \
    --query "name" \
    -o tsv 2>/dev/null || true)

echo "ℹ️ Alert rule status: ${alert_status:-<not found>}"

if [ -n "$alert_status" ]; then
    echo "🗑️  Deleting existing alert rule: http-500-errors-alert"
    az monitor metrics alert delete \
        --name "http-500-errors-alert" \
        --resource-group $resource_group || {
            echo "::warning::Failed to delete existing alert rule, continuing..."
        }
fi

echo "🚀 Creating alert rule: http-500-errors-alert"
echo "ℹ️ Alert configuration:"
echo "   - Metric: requests/failed"
echo "   - Threshold: > $error_threshold"
echo "   - Check frequency: $check_frequency"
echo "   - Window size: $window_size"
echo "   - Severity: $severity"

az monitor metrics alert create \
    --name "http-500-errors-alert" \
    --resource-group $resource_group \
    --scopes "$app_insights_id" \
    --description "Alert when there are excessive HTTP 500 errors" \
    --severity $severity \
    --evaluation-frequency $check_frequency \
    --window-size $window_size \
    --condition "count requests/failed > $error_threshold" \
    --action $action_group_id

echo "✅ Alert setup complete!"
