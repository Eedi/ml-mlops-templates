output "identity_id" {
  value = azurerm_load_test.load_test.identity[0].principal_id
}
