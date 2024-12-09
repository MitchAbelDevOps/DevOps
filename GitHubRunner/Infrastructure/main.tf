/**************************************************
Existing Resources
***************************************************/
data "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "log-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}-01"
  resource_group_name = "${var.sharedResourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
}

data "azurerm_virtual_network" "tewheke_vnet" {
  name                = "vnet-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}-01"
  resource_group_name = "${var.networkingResourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
}

data "azurerm_subnet" "runners_subnet" {
  name                 = "snet-${var.resourceSuffix}-${var.environment}-runners-${var.locationSuffix}-01"
  resource_group_name  = "${var.networkingResourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  virtual_network_name = data.azurerm_virtual_network.tewheke_vnet.name
}

data "azurerm_user_assigned_identity" "acr_pull" {
  name                = "uami-acr-pull-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  resource_group_name = "${var.sharedResourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
}

/**************************************************
New Resources
***************************************************/
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
  principal_id         = data.azurerm_user_assigned_identity.acr_pull.principal_id
}

// Container App Environment
resource "azurerm_container_app_environment" "container_app_environment" {
  // Change name to have 01 suffix
  name                               = "cae-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  location                           = var.location
  resource_group_name                = local.fullResourceGroupName
  log_analytics_workspace_id         = data.azurerm_log_analytics_workspace.log_analytics_workspace.id
  infrastructure_subnet_id           = data.azurerm_subnet.runners_subnet.id
  infrastructure_resource_group_name = "rg-caeinfra-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  internal_load_balancer_enabled     = true

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}
