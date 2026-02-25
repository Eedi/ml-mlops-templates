output "registry_name" {
  value       = local.registry_name
  description = "Name of the ML model registry"
}

output "registry_id" {
  value       = azapi_resource.ml_registry.id
  description = "Resource ID of the ML model registry"
}

output "acr_id" {
  value       = azurerm_container_registry.registry_acr.id
  description = "Resource ID of the backing container registry"
}

output "storage_account_id" {
  value       = azurerm_storage_account.registry_storage.id
  description = "Resource ID of the backing storage account"
}
