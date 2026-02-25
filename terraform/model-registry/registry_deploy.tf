module "model_registry" {
  source = "../azureml/modules/model-registry"

  rg_name  = var.resource_group_name
  location = var.location
  prefix   = var.prefix
  postfix  = var.postfix
  tags     = local.tags
}
