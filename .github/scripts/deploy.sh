#!/bin/bash

set -e

# Read parameters
while getopts "w:r:e:n:c:t:" flag
do
  case "${flag}" in
    w) aml_workspace=${OPTARG};;
    r) resource_group=${OPTARG};;
    e) endpoint_name=${OPTARG};;
    n) deployment_name=${OPTARG};;
    c) deployment_config=${OPTARG};;
    t) traffic_percentage=${OPTARG};;
  esac
done



echo "🔧 Setting defaults"
az configure --defaults workspace="$aml_workspace" group="$resource_group"

# Command to set environment variables. ENDPOINT_NAME and IS_LIVE if traffic_percentage > 0
deployment_env_vars="\
--set environment_variables.TRAFFIC_TYPE="$( [ "$traffic_percentage" -gt 0 ] && echo live || echo shadow )" \
--set environment_variables.ENDPOINT_NAME=\"$endpoint_name\""



echo "🔍 Checking if deployment exists..."
deployment_status=$(az ml online-deployment show \
  --name "$deployment_name" \
  --endpoint "$endpoint_name" \
  --query "provisioning_state" \
  -o tsv 2>/dev/null | sed 's/[[:space:]]//g' || true)

echo "ℹ️ Deployment provisioning state: ${deployment_status:-<not found>}"

if [ "$deployment_status" = "Succeeded" ]; then
  echo "✅ Updating existing deployment: $deployment_name"
  az ml online-deployment update -f $deployment_config --name "$deployment_name" --endpoint-name "$endpoint_name" $deployment_env_vars
else
  if [ -n "$deployment_status" ]; then
    echo "⚠️ Deployment exists but is not in 'Succeeded' state. Deleting it."
    az ml online-deployment delete --name "$deployment_name" --endpoint "$endpoint_name" --yes
  fi

  echo "🚀 Creating deployment: $deployment_name"
  az ml online-deployment create -f $deployment_config --name "$deployment_name" --endpoint-name "$endpoint_name" $deployment_env_vars
fi

deploy_status=$(az ml online-deployment show \
  --name "$deployment_name" \
  --endpoint "$endpoint_name" \
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
# az ml online-endpoint invoke --name $endpoint_name --request-file $sample_requests_path/sample_request_0.json
# </test_endpoint>
