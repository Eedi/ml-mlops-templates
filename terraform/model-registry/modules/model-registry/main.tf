terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

locals {
  safe_prefix  = replace(var.prefix, "-", "")
  safe_postfix = replace(var.postfix, "-", "")
  registry_name = var.postfix != "" ? "reg-${var.prefix}-${var.postfix}" : "reg-${var.prefix}"
}

# Backing container registry for the ML model registry
resource "azurerm_container_registry" "registry_acr" {
  name                = "cr${local.safe_prefix}${local.safe_postfix}"
  resource_group_name = var.rg_name
  location            = var.location
  sku                 = var.acr_sku
  admin_enabled       = true

  tags = var.tags
}

# Azure ML Model Registry (via AzAPI since azurerm does not support this resource)
resource "azapi_resource" "ml_registry" {
  type      = "Microsoft.MachineLearningServices/registries@2024-10-01"
  name      = local.registry_name
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.rg_name}"
  location  = var.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      publicNetworkAccess = "Enabled"
      regionDetails = [
        {
          location = var.location
          acrDetails = [
            {
              systemCreatedAcrAccount = {
                acrAccountName = azurerm_container_registry.registry_acr.name
                acrAccountSku  = var.acr_sku
              }
            }
          ]
          storageAccountDetails = [
            {
              systemCreatedStorageAccount = {
                storageAccountHnsEnabled = false
                storageAccountName       = "st${local.safe_prefix}${local.safe_postfix}"
                storageAccountType       = "Standard_LRS"
              }
            }
          ]
        }
      ]
    }
  }
}

data "azurerm_client_config" "current" {}
