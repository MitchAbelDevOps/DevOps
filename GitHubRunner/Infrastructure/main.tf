/**************************************************
Existing Resources
***************************************************/
// NOTE: Need the VNET set up first before bootstrapping can start
data "azurerm_virtual_network" "tewheke_vnet" {
  name                = "vnet-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}-01"
  resource_group_name = "${var.networkingResourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
}

data "azurerm_subnet" "runners_subnet" {
  name                 = "snet-${var.resourceSuffix}-${var.environment}-runners-${var.locationSuffix}-01"
  resource_group_name  = "${var.networkingResourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  virtual_network_name = data.azurerm_virtual_network.tewheke_vnet.name
}

/**************************************************
New Resources
***************************************************/
// TEMP Log Analytics Workspace
// NOTE: We will change to targeting an existing instance in another subscription when it is provisioned, and remove this one
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "log-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}-02"
  location            = var.location
  resource_group_name = local.fullResourceGroupName
  sku                 = "PerGB2018"
  retention_in_days   = 30

  lifecycle {
    prevent_destroy = false
  }
}

// Azure Container Registry UAMI
resource "azurerm_user_assigned_identity" "acr_pull" {
  name                = "uami-acr-pull-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  resource_group_name = local.fullResourceGroupName
  location            = var.location
}

// Container Registry
resource "azurerm_container_registry" "container_registry" {
  name                = "acr${var.resourceSuffix}${var.environment}${var.locationSuffix}"
  location            = var.location
  resource_group_name = local.fullResourceGroupName
  sku                 = "Basic"
  admin_enabled       = true
}

// ACR Pull UAMI role assignment
resource "azurerm_role_assignment" "uami_role_assignment" {
  scope                = azurerm_container_registry.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.acr_pull.principal_id
}

# // Container App Environment
# resource "azurerm_container_app_environment" "container_app_environment" {
#   // Change name to have 01 suffix
#   name                               = "cae-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
#   location                           = var.location
#   resource_group_name                = local.fullResourceGroupName
#   log_analytics_workspace_id         = azurerm_log_analytics_workspace.log_analytics_workspace.id
#   infrastructure_subnet_id           = data.azurerm_subnet.runners_subnet.id
#   infrastructure_resource_group_name = "rg-caeinfra-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
#   internal_load_balancer_enabled     = true

#   workload_profile {
#     name                  = "Consumption"
#     workload_profile_type = "Consumption"
#   }
# }
