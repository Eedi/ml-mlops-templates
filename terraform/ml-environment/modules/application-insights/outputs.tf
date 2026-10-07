output "id" {
  value = azurerm_application_insights.appi.id
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.la.id
}

output "log_analytics_workspace_guid" {
  value = azurerm_log_analytics_workspace.la.workspace_id
}
