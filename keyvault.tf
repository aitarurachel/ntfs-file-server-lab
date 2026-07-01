data "azurerm_client_config" "current" {}
# random_id generates an 8-char hex suffix — Key Vault names must be globally unique
resource "random_id" "kv_suffix" { byte_length = 4 }

resource "azurerm_key_vault" "lab_kv" {
  name                       = "kv-fslab-${random_id.kv_suffix.hex}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true # REQUIRED — without this, 403 on all secret ops
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# Grant whoever ran az login permission to write secrets.
# current.object_id resolves dynamically to the logged-in identity.
resource "azurerm_role_assignment" "kv_deployer_access" {
  scope                = azurerm_key_vault.lab_kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# depends_on ensures the role assignment propagates before Terraform
# tries to write the secret — without this you get a 403 error.
resource "azurerm_key_vault_secret" "admin_password" {
  name         = "vm-admin-password"
  value        = var.admin_password
  key_vault_id = azurerm_key_vault.lab_kv.id
  depends_on   = [azurerm_role_assignment.kv_deployer_access]
  tags = {
    ManagedBy = "Terraform"
  }
}

