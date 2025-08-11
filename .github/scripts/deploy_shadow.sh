#!/bin/bash

set -e

# Treat unset, empty, or zero (string or number) as "not set"
is_set() {
    local val="$1"
    [[ -n "$val" && "$val" != "0" ]]
}

# Check if required environment variables are set
if ! is_set "$endpoint_name" || ! is_set "$deployment_name" || ! is_set "$shadow_deployment_name"; then
    echo "Error: Missing required environment variables: endpoint_name, deployment_name, shadow_deployment_name"
    exit 1
fi


# Decisioning whether to update/create a shadow deployment or update live traffic routing
# We don't want to do both at the same time because the shadow deployment should be checked before sending traffic to it.
if is_set "$shadow_deployment_traffic_percentage" && is_set "$deployment_name"; then
    if is_set "$shadow_deployment_config" || is_set "$shadow_deployment_mirror_percentage"; then
        echo "Cannot both update live traffic routing and create/update shadow deployment at the same time."
        exit 1
    fi
    create_or_update_shadow_deployment="false"
    update_live_traffic="true"
    primary_deployment_traffic_percentage=$((100-$shadow_deployment_traffic_percentage))
elif is_set "$shadow_deployment_mirror_percentage" && is_set "$shadow_deployment_config"; then
    echo "Creating/updating shadow deployment: $shadow_deployment_name"
    create_or_update_shadow_deployment="true"
    update_live_traffic="false"
else
    echo "No shadow deployment or live traffic routing updates specified."
    exit 0
fi

# =============================================================================
# Update live traffic routing OR create/update shadow deployment
# =============================================================================

echo "🔍 Checking if shadow deployment exists..."
shadow_deployment_status=$(az ml online-deployment show \
  --name "$shadow_deployment_name" \
  --endpoint "$endpoint_name" \
  --query "provisioning_state" \
  -o tsv 2>/dev/null | sed 's/[[:space:]]//g' || true)


if [ $update_live_traffic = "true" ]; then
    echo "Updating live traffic routing for shadow deployment: $shadow_deployment_name"
    if [ "$shadow_deployment_status" = "Succeeded" ]; then
        echo "✅ Shadow deployment $shadow_deployment_name exists and is in 'Succeeded' state."
        # If successful shadow deployment exists we may update traffic routing
        az ml online-endpoint update --name $endpoint_name --traffic "${shadow_deployment_name}=${shadow_deployment_traffic_percentage} ${deployment_name}=${primary_deployment_traffic_percentage}"
    elif [ -n "$shadow_deployment_status" ]; then
        echo "⚠️ Shadow deployment deployment exists but is not in 'Succeeded' state."
        echo "Deleting shadow deployment: $shadow_deployment_name. To assign traffic to a shadow deployment, it must be in 'Succeeded' state."
        az ml online-deployment delete --name "$shadow_deployment_name" --endpoint "$endpoint_name" --yes
    else
        echo "ℹ️ No existing shadow deployment found. Live traffic routing will not be updated."
    fi
elif [ $create_or_update_shadow_deployment = "true" ]; then
    echo "Creating or updating shadow deployment: $shadow_deployment_name"
    if [ "$shadow_deployment_status" = "Succeeded" ]; then
        echo "✅ Shadow deployment $shadow_deployment_name exists and is in 'Succeeded' state. Updating it."
        az ml online-deployment update --endpoint_name $endpoint_name --name $shadow_deployment_name -f shadow_deployment_config
    elif [ -n "$shadow_deployment_status" ]; then
        echo "⚠️ Shadow deployment exists but is not in 'Succeeded' state. Deleting and recreating it."
        az ml online-deployment delete --name "$shadow_deployment_name" --endpoint "$endpoint_name" --yes
        echo "🚀 Creating new shadow deployment: $shadow_deployment_name"
        az ml online-deployment create --endpoint_name $endpoint_name --name $shadow_deployment_name -f shadow_deployment_config
    else
        echo "ℹ️ No existing shadow deployment found. Creating new shadow deployment: $shadow_deployment_name"
        az ml online-deployment create --endpoint_name $endpoint_name --name $shadow_deployment_name -f shadow_deployment_config
    fi
    echo "🔄 Setting shadow deployment traffic to $shadow_deployment_mirror_percentage%"
    az ml online-endpoint update --name $endpoint_name --mirror-traffic "${shadow_deployment_name}=${shadow_deployment_mirror_percentage}"
else
    echo "No live traffic routing updates specified."
fi

