/**************************************************
Existing Resources
***************************************************/
data "azurerm_subnet" "functionapps_subnet" {
  name                 = "snet-${var.resourceSuffix}-${var.environmentGroup}-apps-${var.locationSuffix}"
  resource_group_name  = local.networkResourceGroupName
  virtual_network_name = "vnet-${var.resourceSuffix}-${var.environmentGroup}-${var.locationSuffix}"
}

data "azurerm_subnet" "runner_subnet" {
  name                 = "snet-${var.resourceSuffix}-${var.environmentGroup}-runners-${var.locationSuffix}"
  resource_group_name  = local.networkResourceGroupName
  virtual_network_name = "vnet-${var.resourceSuffix}-${var.environmentGroup}-${var.locationSuffix}"
}

data "azurerm_subnet" "private_endpoint_subnet" {
  name                 = "snet-${var.resourceSuffix}-${var.environmentGroup}-pep-${var.locationSuffix}"
  resource_group_name  = local.networkResourceGroupName
  virtual_network_name = "vnet-${var.resourceSuffix}-${var.environmentGroup}-${var.locationSuffix}"
}

data "azurerm_private_dns_zone" "apps_private_dns_zone" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = local.networkResourceGroupName
}

data "azurerm_private_dns_zone" "files_private_dns_zone" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = local.networkResourceGroupName
}

data "azurerm_private_dns_zone" "blob_private_dns_zone" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.networkResourceGroupName
}

data "azurerm_private_dns_zone" "tables_private_dns_zone" {
  name                = "privatelink.table.core.windows.net"
  resource_group_name = local.networkResourceGroupName
}

data "azurerm_private_dns_zone" "queues_private_dns_zone" {
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = local.networkResourceGroupName
}

data "azurerm_user_assigned_identity" "keyvault_secret_reader" {
  name                = "uami-kv-reader-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  resource_group_name = local.sharedResourceGroupName
}

data "azurerm_application_insights" "application_insights" {
  name                = "appi-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  resource_group_name = local.sharedResourceGroupName
}

data "azurerm_service_plan" "appservice_plan" {
  name                = "asp-fa-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  resource_group_name = local.sharedResourceGroupName
}

data "azurerm_client_config" "current" {}

/**************************************************
New Resources
***************************************************/
// Function App Dedicated Storage Account
resource "azurerm_storage_account" "functionapp_storage" {
  name                = local.storageAccountName
  resource_group_name = local.fullResourceGroupName
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "ZRS"

  public_network_access_enabled = true
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
    virtual_network_subnet_ids = [
      data.azurerm_subnet.functionapps_subnet.id,
      data.azurerm_subnet.runner_subnet.id
    ]
  }

  lifecycle {
    ignore_changes = [network_rules.0.default_action]
  }

  tags = var.tags
}

// Function App File Share
resource "azurerm_storage_share" "storage_fileservice" {
  name               = local.functionAppName
  storage_account_id = azurerm_storage_account.functionapp_storage.id
  quota              = 5120
  access_tier        = "TransactionOptimized"

  depends_on = [
    azurerm_storage_account.functionapp_storage
  ]
}

# // Function App Deploy Slot File Share
# resource "azurerm_storage_share" "storage_fileservice_slot" {
#   name               = "${local.functionAppName}-${local.slotName}"
#   storage_account_id = azurerm_storage_account.functionapp_storage.id
#   quota              = 5120
#   access_tier        = "TransactionOptimized"

#   depends_on = [
#     azurerm_storage_account.functionapp_storage
#   ]
# }

// Function App
resource "azurerm_windows_function_app" "functionapp" {
  name                = local.functionAppName
  resource_group_name = local.fullResourceGroupName
  location            = var.location

  service_plan_id            = data.azurerm_service_plan.appservice_plan.id
  storage_account_name       = azurerm_storage_account.functionapp_storage.name
  storage_account_access_key = azurerm_storage_account.functionapp_storage.primary_access_key

  identity {
    type = "SystemAssigned, UserAssigned"
    identity_ids = [
      data.azurerm_user_assigned_identity.keyvault_secret_reader.id
    ]
  }

  public_network_access_enabled   = true
  virtual_network_subnet_id       = data.azurerm_subnet.functionapps_subnet.id
  key_vault_reference_identity_id = data.azurerm_user_assigned_identity.keyvault_secret_reader.id

  storage_account {
    access_key   = azurerm_storage_account.functionapp_storage.primary_access_key
    account_name = azurerm_storage_account.functionapp_storage.name
    name         = azurerm_storage_account.functionapp_storage.name
    share_name   = local.functionAppName
    type         = "AzureFiles"
  }

  app_settings = local.allAppSettings
  https_only   = true
  sticky_settings {
    app_setting_names = ["WEBSITE_OVERRIDE_STICKY_DIAGNOSTICS_SETTINGS"]
  }

  site_config {
    always_on                        = true
    vnet_route_all_enabled           = true
    use_32_bit_worker                = false
    runtime_scale_monitoring_enabled = true

    application_stack {
      dotnet_version              = "v8.0"
      use_dotnet_isolated_runtime = true
    }

    ip_restriction {
      name                      = "Runner Subnet"
      action                    = "Allow"
      virtual_network_subnet_id = data.azurerm_subnet.runner_subnet.id
    }
    ip_restriction_default_action     = "Deny"
    scm_ip_restriction_default_action = "Deny"
    scm_use_main_ip_restriction       = true
  }

  depends_on = [
    azurerm_storage_share.storage_fileservice
  ]

  tags = var.tags

  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_CONTENTSHARE"],
      storage_account
    ]
  }
}

# // Function App deployment slot
# resource "azurerm_windows_function_app_slot" "deploy_slot" {
#   name            = "deploy-slot"
#   function_app_id = azurerm_windows_function_app.functionapp.id

#   storage_account_name       = azurerm_storage_account.functionapp_storage.name
#   storage_account_access_key = azurerm_storage_account.functionapp_storage.primary_access_key

#   identity {
#     type = "SystemAssigned, UserAssigned"
#     identity_ids = [
#       data.azurerm_user_assigned_identity.keyvault_secret_reader.id
#     ]
#   }

#   public_network_access_enabled   = true
#   virtual_network_subnet_id       = data.azurerm_subnet.functionapps_subnet.id
#   key_vault_reference_identity_id = data.azurerm_user_assigned_identity.keyvault_secret_reader.id


#   storage_account {
#     access_key   = azurerm_storage_account.functionapp_storage.primary_access_key
#     account_name = azurerm_storage_account.functionapp_storage.name
#     name         = azurerm_storage_account.functionapp_storage.name
#     share_name   = "${local.functionAppName}-${local.slotName}"
#     type         = "AzureFiles"
#   }

#   app_settings = local.allSlotAppSettings

#   site_config {
#     always_on              = true
#     vnet_route_all_enabled = true
#     application_stack {
#       dotnet_version              = "v8.0"
#       use_dotnet_isolated_runtime = true
#     }

#     ip_restriction {
#       name                      = "Runner Subnet"
#       action                    = "Allow"
#       virtual_network_subnet_id = data.azurerm_subnet.runner_subnet.id
#     }
#     ip_restriction_default_action     = "Deny"
#     scm_ip_restriction_default_action = "Deny"
#     scm_use_main_ip_restriction       = true
#   }

#   depends_on = [
#     azurerm_storage_share.storage_fileservice_slot,
#     azurerm_windows_function_app.functionapp
#   ]

#   tags = var.tags

#   lifecycle {
#     ignore_changes = [
#       app_settings["WEBSITE_CONTENTSHARE"],
#       storage_account
#     ]
#   }
# }

// Function App Private Endpoint
// NOTE: Deploys in networking resource group, not the shared
module "functionapp_private_endpoint" {
  source                         = "git::https://github.com/MOJNZ-Default/azure-devops-resources//TerraformModules/PrivateEndpoints"
  name                           = "pep-${local.functionAppName}"
  location                       = var.location
  resource_group_name            = local.networkResourceGroupName
  subnet_id                      = data.azurerm_subnet.private_endpoint_subnet.id
  private_connection_resource_id = azurerm_windows_function_app.functionapp.id
  is_manual_connection           = false
  subresource_name               = "sites"
  private_dns_zone_group_name    = "${title(replace("function-${var.functionAppPurpose}-${var.resourceSuffix}", "-", ""))}PrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [data.azurerm_private_dns_zone.apps_private_dns_zone.id]

  depends_on = [azurerm_windows_function_app.functionapp]
}

# // Function App Slot Private Endpoint
# // NOTE: Deploys in networking resource group, not the shared
# module "functionapp_deployslot_private_endpoint" {
#   source                         = "git::https://github.com/MOJNZ-Default/azure-devops-resources//TerraformModules/PrivateEndpoints"
#   name                           = "pep-${local.functionAppName}-deploy-slot"
#   location                       = var.location
#   resource_group_name            = local.networkResourceGroupName
#   subnet_id                      = data.azurerm_subnet.private_endpoint_subnet.id
#   private_connection_resource_id = azurerm_windows_function_app.functionapp.id
#   is_manual_connection           = false
#   subresource_name               = "sites-deploy-slot"
#   private_dns_zone_group_name    = "${title(replace("function-${var.functionAppPurpose}-${var.resourceSuffix}", "-", ""))}DeploySlotPrivateDnsZoneGroup"
#   private_dns_zone_group_ids     = [data.azurerm_private_dns_zone.apps_private_dns_zone.id]

#   depends_on = [azurerm_windows_function_app_slot.deploy_slot]
# }

// Storage Files Private Endpoint
// NOTE: Deploys in networking resource group, not the shared
module "storage_files_private_endpoint" {
  source                         = "git::https://github.com/MOJNZ-Default/azure-devops-resources//TerraformModules/PrivateEndpoints"
  name                           = "pep-${local.storageAccountName}-files"
  location                       = var.location
  resource_group_name            = local.networkResourceGroupName
  subnet_id                      = data.azurerm_subnet.private_endpoint_subnet.id
  private_connection_resource_id = azurerm_storage_account.functionapp_storage.id
  is_manual_connection           = false
  subresource_name               = "file"
  private_dns_zone_group_name    = "${title(local.storageAccountName)}FilesPrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [data.azurerm_private_dns_zone.files_private_dns_zone.id]

  depends_on = [
    azurerm_storage_share.storage_fileservice
  ]
}

// Storage Blob Private Endpoint
// NOTE: Deploys in networking resource group, not the shared
module "storage_blob_private_endpoint" {
  source                         = "git::https://github.com/MOJNZ-Default/azure-devops-resources//TerraformModules/PrivateEndpoints"
  name                           = "pep-${local.storageAccountName}-blob"
  location                       = var.location
  resource_group_name            = local.networkResourceGroupName
  subnet_id                      = data.azurerm_subnet.private_endpoint_subnet.id
  private_connection_resource_id = azurerm_storage_account.functionapp_storage.id
  is_manual_connection           = false
  subresource_name               = "blob"
  private_dns_zone_group_name    = "${title(local.storageAccountName)}BlobPrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [data.azurerm_private_dns_zone.blob_private_dns_zone.id]

  depends_on = [
    azurerm_storage_share.storage_fileservice
  ]
}

// Storage Tables Private Endpoint
// NOTE: Deploys in networking resource group, not the shared
module "storage_tables_private_endpoint" {
  source                         = "git::https://github.com/MOJNZ-Default/azure-devops-resources//TerraformModules/PrivateEndpoints"
  name                           = "pep-${local.storageAccountName}-table"
  location                       = var.location
  resource_group_name            = local.networkResourceGroupName
  subnet_id                      = data.azurerm_subnet.private_endpoint_subnet.id
  private_connection_resource_id = azurerm_storage_account.functionapp_storage.id
  is_manual_connection           = false
  subresource_name               = "table"
  private_dns_zone_group_name    = "${title(local.storageAccountName)}TablePrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [data.azurerm_private_dns_zone.tables_private_dns_zone.id]

  depends_on = [
    azurerm_storage_share.storage_fileservice
  ]
}

// Storage Queues Private Endpoint
// NOTE: Deploys in networking resource group, not the shared
module "storage_queues_private_endpoint" {
  source                         = "git::https://github.com/MOJNZ-Default/azure-devops-resources//TerraformModules/PrivateEndpoints"
  name                           = "pep-${local.storageAccountName}-queue"
  location                       = var.location
  resource_group_name            = local.networkResourceGroupName
  subnet_id                      = data.azurerm_subnet.private_endpoint_subnet.id
  private_connection_resource_id = azurerm_storage_account.functionapp_storage.id
  is_manual_connection           = false
  subresource_name               = "queue"
  private_dns_zone_group_name    = "${title(local.storageAccountName)}QueuePrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [data.azurerm_private_dns_zone.queues_private_dns_zone.id]

  depends_on = [
    azurerm_storage_share.storage_fileservice
  ]
}

resource "null_resource" "set_storage_default_deny" {
  provisioner "local-exec" {
    command = <<EOT
      az storage account update \
        --name ${azurerm_storage_account.functionapp_storage.name} \
        --resource-group ${azurerm_storage_account.functionapp_storage.resource_group_name} \
        --default-action Deny
    EOT
  }

  triggers = {
    always_trigger = timestamp()
  }

  depends_on = [
    azurerm_windows_function_app.functionapp
  ]
}