output "name" {
  value = azurerm_machine_learning_workspace.mlw.name
}

output "principal_id" {
  value = azurerm_machine_learning_workspace.mlw.identity[0].principal_id
}
