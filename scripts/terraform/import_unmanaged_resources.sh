#!/usr/bin/env bash
set -e

echo "Ensuring Key Vault access policy is in state"

TF_RESOURCE_NAME="module.aml_workspace.azurerm_key_vault_access_policy.ml_workspace"

# Check if the ML workspace is already in the Terraform state
if terraform state show "module.aml_workspace.azurerm_machine_learning_workspace.mlw" >/dev/null 2>&1; then

  # If the Key Vault access policy is not already in state
  if ! terraform state show "$TF_RESOURCE_NAME" >/dev/null 2>&1; then

    echo "Access policy not found in state. Attempting import..."

    # Get the principal ID of the ML workspace
    PRINCIPAL_ID=$(az resource show \
    --resource-group "$PROJECT_RESOURCE_GROUP_NAME" \
    --resource-type "Microsoft.MachineLearningServices/workspaces" \
    --name "$AML_WORKSPACE" \
    --query "identity.principalId" \
    -o tsv 2>/dev/null | sed 's/[[:space:]]//g')  # Suppress errors, strip whitespace

    if [ -z "$PRINCIPAL_ID" ]; then
      echo "Failed to retrieve principal ID. Skipping import."
    else

      echo "Retrieved principal ID. Proceeding with import..."

      # Construct the full resource ID
      RESOURCE_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$PROJECT_RESOURCE_GROUP_NAME/providers/Microsoft.KeyVault/vaults/$KEYVAULT_NAME/objectId/$PRINCIPAL_ID"

      # Import the resource
      terraform import "$TF_RESOURCE_NAME" "$RESOURCE_ID"
    fi

  else
    echo "Access policy already managed in state. Skipping import."
  fi

else
  echo "ML workspace not found in Terraform state. Skipping access policy import."
fi
