data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                = "kv-${var.prefix}-${var.postfix}${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  tags = var.tags
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create",
      "Get",
    ]

    secret_permissions = [
      "Set",
      "Get",
      "Delete",
      "Purge",
      "Recover",
      "List"
    ]
  }
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = var.load_test_identity_id
    key_permissions = [
      "Get",
    ]
    secret_permissions = [
      "Get"
    ]
  }

  # The inline access_policy blocks above are authoritative: by default every
  # apply resets the vault's entire access-policy list to exactly what is
  # declared here and DELETES anything else. Other identities legitimately get
  # policies out-of-band — most importantly the AML workspace managed identity
  # (managed by the separate azurerm_key_vault_access_policy.ml_workspace
  # resource in the aml-workspace module) and any online-endpoint identities
  # AML grants at deploy time. Without ignoring access_policy, re-applying an
  # existing environment strips those policies and cuts off the workspace's
  # access to its own key vault, breaking endpoint/portal key access.
  # Ignore access_policy so the inline blocks only seed a greenfield create and
  # drift on the policy list is left to the dedicated access-policy resources.
  lifecycle {
    ignore_changes = [access_policy]
  }
}
