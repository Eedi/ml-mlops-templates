variable "resource_group_name" {
  type        = string
  description = "Resource group for the shared model registry"
}

variable "location" {
  type        = string
  description = "Location of the resource group and modules"
}

variable "prefix" {
  type        = string
  description = "Prefix for module names"
}

variable "postfix" {
  type        = string
  description = "Postfix for module names (e.g. il-shared, anet-shared)"
}

variable "environment" {
  type        = string
  description = "Environment information"
}

variable "repo_name" {
  type        = string
  description = "Repository identifier used in resource tagging"
}

# Variables passed by terraform_azureml.yml but unused by this root config
variable "enable_aml_computecluster" {
  description = "Unused - required for terraform_azureml.yml compatibility"
  default     = false
}

variable "enable_monitoring" {
  description = "Unused - required for terraform_azureml.yml compatibility"
  default     = false
}

variable "slack_webhook_url" {
  type        = string
  description = "Unused - required for terraform_azureml.yml compatibility"
  default     = ""
}
