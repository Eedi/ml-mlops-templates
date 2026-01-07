#!/usr/bin/env bash

set -euo pipefail

: "${pipeline_config_path:?Environment variable 'pipeline_config_path' must be set}"
: "${aml_workspace:?Environment variable 'aml_workspace' must be set}"
: "${resource_group:?Environment variable 'resource_group' must be set}"

if [[ ! -f "$pipeline_config_path" ]]; then
  echo "Error: Pipeline definition '$pipeline_config_path' not found."
  exit 1
fi

echo "🔧 Setting Azure ML defaults (workspace=$aml_workspace, resource_group=$resource_group)"
az configure --defaults workspace="$aml_workspace" group="$resource_group"

echo "🚀 Submitting training pipeline: $pipeline_config_path"
az ml job create -f "$pipeline_config_path"
echo "✅ Training pipeline submitted"
