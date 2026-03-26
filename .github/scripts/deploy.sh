#!/bin/bash

set -e

# Read parameters
while getopts "w:r:e:n:c:t:s:q:b:" flag
do
  case "${flag}" in
    w) aml_workspace=${OPTARG};;
    r) resource_group=${OPTARG};;
    e) endpoint_name=${OPTARG};;
    n) deployment_name=${OPTARG};;
    c) deployment_config=${OPTARG};;
    t) traffic_percentage=${OPTARG};;
    s) storage_account=${OPTARG};;
    q) enable_queue_logging=${OPTARG};;
    b) build_sha=${OPTARG};;
  esac
done

# Default to enabled for backwards compatibility
enable_queue_logging="${enable_queue_logging:-true}"



echo "🔧 Setting defaults"
az configure --defaults workspace="$aml_workspace" group="$resource_group"


# Set variables for log storage
traffic_type="$( [ "$traffic_percentage" -gt 0 ] && echo live || echo shadow )" # traffic type is used to direct logs of shadow traffic to a different queue/container
endpoint_identity=$(az ml online-endpoint show --name $endpoint_name --query "identity.principal_id" -o tsv 2>/dev/null | sed 's/[[:space:]]//g' || true)
storage_account_id=$(az storage account show --name $storage_account --query "id" -o tsv 2>/dev/null | sed 's/[[:space:]]//g' || true)
queue_name="q-$(echo $endpoint_name | tr '[:upper:]' '[:lower:]')-$traffic_type"
queue_id="${storage_account_id}/queueServices/default/queues/${queue_name}"
staging_container_name="blob-$queue_name"
container_id=$storage_account_id/blobServices/default/containers/$staging_container_name

if [ "$enable_queue_logging" = "true" ]; then
  echo "🔍 Ensuring log storage resources exist..."
  echo "Creating queue"
  az storage queue create --name $queue_name --account-name $storage_account --auth-mode login
  echo "Assigning Storage Queue Data Contributor role to endpoint identity"
  az role assignment create --assignee-object-id $endpoint_identity --assignee-principal-type ServicePrincipal --role "Storage Queue Data Contributor" --scope $queue_id
  echo "Creating blob container"
  az storage container create --name $staging_container_name --account-name $storage_account --auth-mode login
  echo "Assigning Storage Blob Data Contributor role to endpoint identity"
  az role assignment create --assignee-object-id $endpoint_identity --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope $container_id

  deployment_env_vars="\
--set environment_variables.TRAFFIC_TYPE=$traffic_type \
--set environment_variables.ENDPOINT_NAME=$endpoint_name \
--set environment_variables.QUEUE_NAME=$queue_name \
--set environment_variables.STAGING_CONTAINER_NAME=$staging_container_name \
--set environment_variables.LOGGING_MODE=remote \
--set environment_variables.AZURE_STORAGE_ACCOUNT_NAME=$storage_account \
${build_sha:+--set environment_variables.BUILD_SHA=$build_sha}"
else
  echo "ℹ️ Queue logging disabled — skipping log storage setup"
  deployment_env_vars="\
--set environment_variables.TRAFFIC_TYPE=$traffic_type \
--set environment_variables.ENDPOINT_NAME=$endpoint_name \
--set environment_variables.LOGGING_MODE=disabled \
${build_sha:+--set environment_variables.BUILD_SHA=$build_sha}"
fi


echo "🔍 Checking if deployment exists..."
deployment_status=$(az ml online-deployment show \
  --name "$deployment_name" \
  --endpoint "$endpoint_name" \
  --query "provisioning_state" \
  -o tsv 2>/dev/null | sed 's/[[:space:]]//g' || true)

echo "ℹ️ Deployment provisioning state: ${deployment_status:-<not found>}"

if [ "$deployment_status" = "Succeeded" ]; then
  # instance_type is immutable on update — must delete+recreate if changed
  live_instance_type=$(az ml online-deployment show \
    --name "$deployment_name" \
    --endpoint "$endpoint_name" \
    --query "instance_type" \
    -o tsv 2>/dev/null | sed 's/[[:space:]]//g' || true)
  desired_instance_type=$(yq eval '.instance_type' "$deployment_config" | sed 's/[[:space:]]//g')

  if [ -n "$desired_instance_type" ] && [ "$live_instance_type" != "$desired_instance_type" ]; then
    echo "⚠️ instance_type changed ($live_instance_type → $desired_instance_type). Deleting deployment to recreate."
    echo "🔀 Zeroing traffic before delete"
    az ml online-endpoint update --name "$endpoint_name" --traffic "$deployment_name=0" || true
    az ml online-deployment delete --name "$deployment_name" --endpoint "$endpoint_name" --yes
    deployment_status=""
  fi
fi

if [ "$deployment_status" = "Succeeded" ]; then
  echo "✅ Updating existing deployment: $deployment_name"

  # Copy base config
  tmp_yaml=$(mktemp)
  cp "$deployment_config" "$tmp_yaml"

  # Append or replace environment variables in YAML
  if [ "$enable_queue_logging" = "true" ]; then
    yq eval "
      .environment_variables.TRAFFIC_TYPE = \"$traffic_type\" |
      .environment_variables.ENDPOINT_NAME = \"$endpoint_name\" |
      .environment_variables.QUEUE_NAME = \"$queue_name\" |
      .environment_variables.STAGING_CONTAINER_NAME = \"$staging_container_name\" |
      .environment_variables.LOGGING_MODE = \"remote\" |
      .environment_variables.AZURE_STORAGE_ACCOUNT_NAME = \"$storage_account\" |
      .environment_variables.BUILD_SHA = \"${build_sha:-}\"
    " -i "$tmp_yaml"
  else
    yq eval "
      .environment_variables.TRAFFIC_TYPE = \"$traffic_type\" |
      .environment_variables.ENDPOINT_NAME = \"$endpoint_name\" |
      .environment_variables.LOGGING_MODE = \"disabled\" |
      .environment_variables.BUILD_SHA = \"${build_sha:-}\"
    " -i "$tmp_yaml"
  fi

  az ml online-deployment update -f "$tmp_yaml" --name "$deployment_name" --endpoint-name "$endpoint_name"
else
  if [ -n "$deployment_status" ]; then
    echo "⚠️ Deployment exists but is not in 'Succeeded' state. Deleting it."
    echo "🔀 Zeroing traffic before delete"
    az ml online-endpoint update --name "$endpoint_name" --traffic "$deployment_name=0" || true
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
