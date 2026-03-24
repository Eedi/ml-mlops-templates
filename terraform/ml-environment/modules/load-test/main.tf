resource "azurerm_load_test" "load_test" {
  name                = "lt${var.prefix}${var.postfix}${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}
