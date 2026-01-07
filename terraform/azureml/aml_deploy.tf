# Storage account
module "storage_account_aml" {
  source = "./modules/storage-account"

  rg_name                             = var.resource_group_name
  location                            = var.location
  prefix                              = var.prefix
  postfix                             = var.postfix
  env                                 = var.environment
  hns_enabled                         = false
  firewall_bypass                     = ["AzureServices"]
  firewall_virtual_network_subnet_ids = []
  tags                                = local.tags
}

# Load test
module "load_test" {
  source = "./modules/load-test"

  resource_group_name = var.resource_group_name
  location            = var.location
  prefix              = var.prefix
  postfix             = var.postfix
  env                 = var.environment
  tags                = local.tags
}

# Azure monitor resources, including action group for Slack notifications
module "monitor" {
  source = "./modules/monitor"

  resource_group_name = var.resource_group_name
  location            = var.location

  prefix  = var.prefix
  postfix = var.postfix
  env     = var.environment

  slack_webhook_url = var.slack_webhook_url

  tags = local.tags
}

# Key vault
module "key_vault" {
  source = "./modules/key-vault"

  resource_group_name   = var.resource_group_name
  location              = var.location
  prefix                = var.prefix
  postfix               = var.postfix
  env                   = var.environment
  load_test_identity_id = module.load_test.identity_id
  tags                  = local.tags
}

# Application insights
module "application_insights" {
  source = "./modules/application-insights"

  rg_name  = var.resource_group_name
  location = var.location

  prefix  = var.prefix
  postfix = var.postfix
  env     = var.environment

  tags = local.tags
}

# Container registry
module "container_registry" {
  source = "./modules/container-registry"

  rg_name  = var.resource_group_name
  location = var.location

  prefix  = var.prefix
  postfix = var.postfix
  env     = var.environment

  tags = local.tags
}


# Azure Machine Learning workspace
module "aml_workspace" {
  source = "./modules/aml-workspace"

  rg_name  = var.resource_group_name
  location = var.location

  prefix  = var.prefix
  postfix = var.postfix
  env     = var.environment

  storage_account_id      = module.storage_account_aml.id
  key_vault_id            = module.key_vault.id
  application_insights_id = module.application_insights.id
  container_registry_id   = module.container_registry.id

  enable_aml_computecluster = var.enable_aml_computecluster
  storage_account_name      = module.storage_account_aml.name

  tags = local.tags
}


# module "data_explorer" {
#   source = "./modules/data-explorer"

#   rg_name  = module.resource_group.name
#   location = module.resource_group.location

#   prefix            = var.prefix
#   postfix           = var.postfix
#   env               = var.environment
#   key_vault_id      = module.key_vault.id
#   enable_monitoring = var.enable_monitoring

#   client_secret = var.client_secret

#   tags = local.tags
# }
