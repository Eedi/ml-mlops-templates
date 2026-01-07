variable "resource_group_name" {
  type        = string
  description = "Resource group for the project"
}

variable "location" {
  type        = string
  description = "Location of the resource group and modules"
}

variable "prefix" {
  type        = string
  description = "Prefix for module names"
}

variable "environment" {
  type        = string
  description = "Environment information"
}

variable "postfix" {
  type        = string
  description = "Postfix for module names"
}

variable "enable_aml_computecluster" {
  description = "Variable to enable or disable AML compute cluster"
}

variable "enable_monitoring" {
  description = "Variable to enable or disable Monitoring"
}

variable "slack_webhook_url" {
  type        = string
  description = "Slack webhook URL for alerting"
}

variable "repo_name" {
  type        = string
  description = "Repository identifier used in resource tagging"
}
