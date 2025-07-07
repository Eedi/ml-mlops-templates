#!/bin/bash

set -e

# Check if required environment variables are set
if [[ -z "$aml_workspace" || -z "$resource_group" || -z "$ml_env_name" || -z "$ml_env_description" || -z "$target_layer" || -z "$tags" ]]; then
    echo "Error: Missing required environment variables."
    exit 1
fi

# Configure Azure defaults
az configure --defaults workspace=$aml_workspace group=$resource_group

# Login to ACR
ACR_NAME=$(az ml workspace show --query container_registry --output tsv | rev | cut -d'/' -f1 | rev | tr -d '\r\n')
az acr login --name "$ACR_NAME"

# Build images from pyproject.toml and push to ACR

## TRAINING ENVIRONMENT ##
LOCAL_TAG="$ml_env_name:latest"
REMOTE_TAG="$ACR_NAME.azurecr.io/$LOCAL_TAG"
CACHE_IMAGE="$ACR_NAME.azurecr.io/$ml_env_name:buildcache"

if docker buildx inspect | grep 'Driver:\s*docker-container'; then
  echo "Running on docker-container driver (gha), using cache"
  docker buildx build \
    --target "$target_layer" \
    --tag "$REMOTE_TAG" \
    --file Dockerfile \
    --cache-from type=registry,ref="$CACHE_IMAGE" \
    --cache-to type=registry,ref="$CACHE_IMAGE",mode=min \
    --push \
    .

    # Create environment from image in ACR
    az ml environment create --name "$ml_env_name" --description "$ml_env_description" --image "$ACR_NAME.azurecr.io/$ml_env_name" --tags "$tags"
else
  echo "Running on docker driver (local), skipping cache options and acr push"
  docker build \
    --target "$target_layer" \
    --tag "$REMOTE_TAG" \
    --file Dockerfile \
    .
fi
