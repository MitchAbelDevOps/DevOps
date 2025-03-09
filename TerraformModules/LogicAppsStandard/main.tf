/**************************************************
Existing Resources
***************************************************/
data "azurerm_subnet" "logicapps_subnet" {
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

data "azurerm_user_assigned_identity" "sa_blob_reader" {
  name                = "uami-sa-blob-reader-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  resource_group_name = local.sharedResourceGroupName
}


data "azurerm_application_insights" "application_insights" {
  name                = "appi-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  resource_group_name = local.sharedResourceGroupName
}

# Should take the name of the ASP as an input
data "azurerm_service_plan" "appservice_plan" {
  name                = "asp-las-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  resource_group_name = local.sharedResourceGroupName
}

data "azurerm_client_config" "current" {}

/**************************************************
New Resources
***************************************************/
// Logic App Dedicated Storage Account
resource "azurerm_storage_account" "logicapp_storage" {
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
      data.azurerm_subnet.logicapps_subnet.id,
      data.azurerm_subnet.runner_subnet.id
    ]
  }

  lifecycle {
    ignore_changes = [network_rules.0.default_action]
  }

  tags = var.tags
}

// Logic App File Share
resource "azurerm_storage_share" "storage_fileservice" {
  name               = local.logicAppName
  storage_account_id = azurerm_storage_account.logicapp_storage.id
  quota              = 5120
  access_tier        = "TransactionOptimized"

  depends_on = [
    azurerm_storage_account.logicapp_storage
  ]
}

# // Logic App Deploy Slot File Share
# resource "azurerm_storage_share" "storage_fileservice_slot" {
#   name               = "${local.logicAppName}-${local.slotName}"
#   storage_account_id = azurerm_storage_account.logicapp_storage.id
#   quota              = 5120
#   access_tier        = "TransactionOptimized"

#   depends_on = [
#     azurerm_storage_account.logicapp_storage
#   ]
# }

// Logic App
resource "azurerm_logic_app_standard" "logicapp_standard" {
  name                = local.logicAppName
  resource_group_name = local.fullResourceGroupName
  location            = var.location

  app_service_plan_id        = data.azurerm_service_plan.appservice_plan.id
  storage_account_name       = azurerm_storage_account.logicapp_storage.name
  storage_account_access_key = azurerm_storage_account.logicapp_storage.primary_access_key

  identity {
    type = "SystemAssigned, UserAssigned"
    identity_ids = [
      data.azurerm_user_assigned_identity.keyvault_secret_reader.id,
      data.azurerm_user_assigned_identity.sa_blob_reader.id
    ]
  }

  public_network_access     = "Enabled"
  virtual_network_subnet_id = data.azurerm_subnet.logicapps_subnet.id

  storage_account_share_name = local.logicAppName

  app_settings = local.allAppSettings
  https_only   = true
  site_config {
    dotnet_framework_version         = "v8.0"
    always_on                        = true
    vnet_route_all_enabled           = true
    use_32_bit_worker_process        = false
    runtime_scale_monitoring_enabled = true

    ip_restriction = local.allIPRestrictions
    scm_ip_restriction          = []
    scm_use_main_ip_restriction = true
  }

  depends_on = [
    module.storage_blob_private_endpoint,
    module.storage_files_private_endpoint,
    module.storage_queues_private_endpoint,
    module.storage_tables_private_endpoint
  ]

  tags = var.tags

  lifecycle {
    ignore_changes = [
      storage_account_share_name
    ]
  }
}

// Supports provisioning of settings not supported by Terraform for now.
// keyVaultReferenceIdentity for forcing Logic App Standard to use Key Vault Managed identitiy
// production slot speicifc setting to allow swaps, known swap bug: https://github.com/Azure/azure-functions-host/issues/8448#issuecomment-1329543434
resource "null_resource" "logicapp_standard_customcommands" {
  provisioner "local-exec" {
    command = <<-EOT
      az login --service-principal --username $ARM_CLIENT_ID --password $ARM_CLIENT_SECRET --tenant $ARM_TENANT_ID
      az account set --subscription "${data.azurerm_client_config.current.subscription_id}"
      az functionapp update -g "${local.fullResourceGroupName}" -n "${local.logicAppName}" --set keyVaultReferenceIdentity="${data.azurerm_user_assigned_identity.keyvault_secret_reader.id}"    
      az functionapp config appsettings set --name "${azurerm_logic_app_standard.logicapp_standard.name}" --resource-group "${local.fullResourceGroupName}" --slot-settings "WEBSITE_OVERRIDE_STICKY_DIAGNOSTICS_SETTINGS=0"
      # az functionapp config appsettings set --name "${azurerm_logic_app_standard.logicapp_standard.name}" --resource-group "${local.fullResourceGroupName}" --slot-settings "AzureFunctionsWebHost__hostid=${local.appHostId}"
  
      # Set IP restriction unmatched rule action to "Deny" for the main site and Kudu (scm) site
      az functionapp config set --resource-group "${local.fullResourceGroupName}" --name "${local.logicAppName}" --generic-configurations "{'ipSecurityRestrictionsDefaultAction':'Deny','scmIpSecurityRestrictionsDefaultAction':'Deny'}"
  EOT
  }

  triggers = {
    always_trigger = timestamp()
  }

  depends_on = [azurerm_logic_app_standard.logicapp_standard]
}

# // Logic App deployment slot 1
# resource "null_resource" "deploy_slot" {
#   provisioner "local-exec" {
#     command = <<-EOT
#       # Check if the deployment slot exists
#       SLOT_EXISTS=$(az functionapp deployment slot list \
#         --name "${azurerm_logic_app_standard.logicapp_standard.name}" \
#         --resource-group "${local.fullResourceGroupName}" \
#         --query "[?name=='deploy-slot'] | length(@)" -o tsv)

#       if [ "$SLOT_EXISTS" -eq 0 ]; then
#         echo "Deployment slot does not exist. Creating it..."
        
#         # Create the deployment slot
#         az functionapp deployment slot create \
#           --name "${azurerm_logic_app_standard.logicapp_standard.name}" \
#           --resource-group "${local.fullResourceGroupName}" \
#           --slot "deploy-slot"

#         # Set WEBSITE_CONTENTSHARE only on initial creation
#         az functionapp config appsettings set \
#           --name "${azurerm_logic_app_standard.logicapp_standard.name}" \
#           --resource-group "${local.fullResourceGroupName}" \
#           --slot "deploy-slot" \
#           --settings "WEBSITE_CONTENTSHARE=${azurerm_storage_share.storage_fileservice_slot.name}"

#         # Set AzureFunctionsWebHost__hostid only on initial creation
#         # az functionapp config appsettings set \
#         #   --name "${azurerm_logic_app_standard.logicapp_standard.name}" \
#         #   --resource-group "${local.fullResourceGroupName}" \
#         #   --slot "deploy-slot" \
#         #   --slot-settings "AzureFunctionsWebHost__hostid=${local.appSlotHostId}"
#       else
#         echo "Deployment slot 'deploy-slot' already exists."
#       fi

#       # Prepare custom app settings as JSON
#       CUSTOM_SETTINGS=$(cat <<EOF
# $(echo '${jsonencode(var.customAppSettings)}' | jq -r 'tojson')
# EOF
#       )

#       echo "Applying custom app settings to the deployment slot..."
#       echo "$CUSTOM_SETTINGS" | jq .
      
#       az functionapp config appsettings set \
#         --name "${azurerm_logic_app_standard.logicapp_standard.name}" \
#         --resource-group "${local.fullResourceGroupName}" \
#         --slot "deploy-slot" \
#         --settings "$CUSTOM_SETTINGS"
#     EOT
#   }

#   triggers = {
#     always_trigger = timestamp()
#   }

#   depends_on = [
#     azurerm_logic_app_standard.logicapp_standard,
#     azurerm_storage_share.storage_fileservice_slot
#   ]
# }

// Logic App Private Endpoint
// NOTE: Deploys in networking resource group, not the shared
module "logicapp_private_endpoint" {
  source                         = "git::https://github.com/MitchAbelDevOps/azure-devops-resources//TerraformModules/PrivateEndpoints"
  name                           = "pep-${local.logicAppName}"
  location                       = var.location
  resource_group_name            = local.networkResourceGroupName
  subnet_id                      = data.azurerm_subnet.private_endpoint_subnet.id
  private_connection_resource_id = azurerm_logic_app_standard.logicapp_standard.id
  is_manual_connection           = false
  subresource_name               = "sites"
  private_dns_zone_group_name    = "${title(replace("logic-${var.logicAppPurpose}-${var.resourceSuffix}", "-", ""))}PrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [data.azurerm_private_dns_zone.apps_private_dns_zone.id]
}

// Storage Files Private Endpoint
// NOTE: Deploys in networking resource group, not the shared
module "storage_files_private_endpoint" {
  source                         = "git::https://github.com/MitchAbelDevOps/azure-devops-resources//TerraformModules/PrivateEndpoints"
  name                           = "pep-${local.storageAccountName}-files"
  location                       = var.location
  resource_group_name            = local.networkResourceGroupName
  subnet_id                      = data.azurerm_subnet.private_endpoint_subnet.id
  private_connection_resource_id = azurerm_storage_account.logicapp_storage.id
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
  source                         = "git::https://github.com/MitchAbelDevOps/azure-devops-resources//TerraformModules/PrivateEndpoints"
  name                           = "pep-${local.storageAccountName}-blob"
  location                       = var.location
  resource_group_name            = local.networkResourceGroupName
  subnet_id                      = data.azurerm_subnet.private_endpoint_subnet.id
  private_connection_resource_id = azurerm_storage_account.logicapp_storage.id
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
  source                         = "git::https://github.com/MitchAbelDevOps/azure-devops-resources//TerraformModules/PrivateEndpoints"
  name                           = "pep-${local.storageAccountName}-table"
  location                       = var.location
  resource_group_name            = local.networkResourceGroupName
  subnet_id                      = data.azurerm_subnet.private_endpoint_subnet.id
  private_connection_resource_id = azurerm_storage_account.logicapp_storage.id
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
  source                         = "git::https://github.com/MitchAbelDevOps/azure-devops-resources//TerraformModules/PrivateEndpoints"
  name                           = "pep-${local.storageAccountName}-queue"
  location                       = var.location
  resource_group_name            = local.networkResourceGroupName
  subnet_id                      = data.azurerm_subnet.private_endpoint_subnet.id
  private_connection_resource_id = azurerm_storage_account.logicapp_storage.id
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
        --name ${azurerm_storage_account.logicapp_storage.name} \
        --resource-group ${azurerm_storage_account.logicapp_storage.resource_group_name} \
        --default-action Deny
    EOT
  }

  triggers = {
    always_trigger = timestamp()
  }

  depends_on = [
    azurerm_logic_app_standard.logicapp_standard
  ]
}