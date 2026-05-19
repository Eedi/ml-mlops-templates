locals {
  workflow_name = "la-slack-translator-${var.prefix}-${var.postfix}-${var.env}"
  trigger_name  = "When_Azure_alert_received"
}

data "azurerm_client_config" "current" {}

# Logic App: translates Azure Common Alert Schema into a Slack-format message
# and POSTs to the existing Slack incoming webhook. Defined via azapi_resource
# so the workflow definition (including runtimeConfiguration.secureData to
# redact the webhook URL from run history) is fully owned by terraform.
resource "azapi_resource" "slack_translator" {
  type      = "Microsoft.Logic/workflows@2019-05-01"
  name      = local.workflow_name
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  location  = var.location
  tags      = var.tags

  body = {
    properties = {
      state      = "Enabled"
      definition = jsondecode(file("${path.module}/workflow-definition.json"))
      parameters = {
        slackWebhookUrl = {
          value = var.slack_webhook_url
        }
      }
    }
  }
}

# Callback URL is itself a SAS-signed secret; export via
# sensitive_response_export_values so it stays out of plan output.
data "azapi_resource_action" "trigger_callback_url" {
  type                             = "Microsoft.Logic/workflows/triggers@2019-05-01"
  resource_id                      = "${azapi_resource.slack_translator.id}/triggers/${local.trigger_name}"
  action                           = "listCallbackUrl"
  method                           = "POST"
  sensitive_response_export_values = ["value"]
}

resource "azurerm_monitor_action_group" "slack_action_group" {
  name                = "ag-${var.prefix}-${var.postfix}-${var.env}"
  resource_group_name = var.resource_group_name
  tags                = var.tags
  short_name          = "Alert Hook"

  webhook_receiver {
    name                    = "slack-translator"
    service_uri             = data.azapi_resource_action.trigger_callback_url.sensitive_output.value
    use_common_alert_schema = true
  }
}
