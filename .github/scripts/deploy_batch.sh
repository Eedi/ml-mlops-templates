#!/bin/bash

set -e

echo "🔧 Setting defaults"
az configure --defaults workspace="$aml_workspace" group="$resource_group"

echo "🔍 Checking if batch deployment exists..."
deployment_status=$(az ml batch-deployment show \
  --name "$batch_deployment_name" \
  --endpoint "$batch_endpoint_name" \
  --query "provisioning_state" \
  -o tsv 2>/dev/null | sed 's/[[:space:]]//g' || true)

echo "ℹ️ Deployment provisioning state: ${deployment_status:-<not found>}"

if [ "$deployment_status" = "Succeeded" ]; then
  echo "✅ Updating existing deployment: $batch_deployment_name"
  az ml batch-deployment update -f "$mlops_path/configs/$batch_deployment_config"
else
  if [ -n "$deployment_status" ]; then
    echo "⚠️ Deployment exists but is not in 'Succeeded' state. Deleting it."
    az ml batch-deployment delete --name "$batch_deployment_name" --endpoint "$batch_endpoint_name" --yes
  fi

  echo "🚀 Creating deployment: $batch_deployment_name"
  az ml batch-deployment create -f "$mlops_path/configs/$batch_deployment_config" --all-traffic
fi

deploy_status=$(az ml batch-deployment show \
  --name "$batch_deployment_name" \
  --endpoint "$batch_endpoint_name" \
  --query "provisioning_state" \
  -o tsv | sed 's/[[:space:]]//g')

echo "ℹ️ Final deployment status: $deploy_status"

if [ "$deploy_status" = "Succeeded" ]; then
  echo "✅ Deployment completed successfully"
else
  echo "❌ Deployment failed"
  exit 1
fi

# <test_endpoint>
# Uncomment and modify the following line to test the endpoint
# az ml online-endpoint invoke --name $batch_endpoint_name --request-file $sample_requests_path/sample_request_0.json
# </test_endpoint>
