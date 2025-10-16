#!/bin/bash

set -e

# Read parameters
while getopts "w:r:e:n:c:t:s:" flag
do
  case "${flag}" in
    w) aml_workspace=${OPTARG};;
    r) resource_group=${OPTARG};;
    e) endpoint_name=${OPTARG};;
    n) deployment_name=${OPTARG};;
    c) deployment_config=${OPTARG};;
    t) traffic_percentage=${OPTARG};;
    s) storage_account=${OPTARG};;
  esac
done



echo "🔧 Setting defaults"
az configure --defaults workspace="$aml_workspace" group="$resource_group"


# Set variables for log storage
traffic_type="$( [ "$traffic_percentage" -gt 0 ] && echo live || echo shadow )" # traffic type is used to direct logs of shadow traffic to a different queue/container
endpoint_identity=$(az ml online-endpoint show --name $endpoint_name --query "identity.principal_id" -o tsv 2>/dev/null | sed 's/[[:space:]]//g' || true)
storage_account_id=$(az storage account show --name $storage_account --query "id" -o tsv 2>/dev/null | sed 's/[[:space:]]//g' || true)
queue_name="q-$(echo $endpoint_name | tr '[:upper:]' '[:lower:]')-$traffic_type"
queue_id="${storage_account_id}/queueServices/default/queues/${queue_name}"
container_name="blob-$queue_name"
container_id=$storage_account_id/blobServices/default/containers/$container_name

echo "🔍 Ensuring log storage resources exist..."
az storage queue create --name $queue_name --account-name $storage_account --auth-mode login
az role assignment create --assignee-object-id $endpoint_identity --assignee-principal-type ServicePrincipal --role "Storage Queue Data Contributor" --scope $queue_id
az storage container create --name $container_name --account-name $storage_account --auth-mode login
az role assignment create --assignee-object-id $endpoint_identity --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope $container_id

# Define environment variables for deployment
deployment_env_vars="\
--set environment_variables.TRAFFIC_TYPE=$traffic_type \
--set environment_variables.ENDPOINT_NAME=$endpoint_name \
--set environment_variables.QUEUE_NAME=$queue_name \
--set environment_variables.CONTAINER_NAME=$container_name \
--set environment_variables.LOGGING_MODE=remote \
--set environment_variables.AZURE_STORAGE_ACCOUNT_NAME=$storage_account"


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
