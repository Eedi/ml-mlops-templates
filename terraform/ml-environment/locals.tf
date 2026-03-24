locals {
  tags = {
    team        = "data-science"
    repo        = var.repo_name
    environment = var.environment
    toolkit     = "terraform"
  }
}
