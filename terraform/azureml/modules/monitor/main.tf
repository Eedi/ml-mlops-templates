resource "azurerm_monitor_action_group" "slack_action_group" {
  name                = "ag-${var.prefix}-${var.postfix}-${var.env}"
  resource_group_name = var.resource_group_name
  tags                = var.tags
  short_name          = "Alert Hook"

  webhook_receiver {
    name                    = "slack-webhook"
    service_uri             = var.slack_webhook_url
    use_common_alert_schema = true
  }

}
