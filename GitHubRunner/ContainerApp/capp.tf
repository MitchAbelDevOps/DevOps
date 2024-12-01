/**************************************************
Existing Resources
***************************************************/
data "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "log-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  resource_group_name = local.fullResourceGroupName
}

data "azurerm_virtual_network" "tewheke_vnet" {
  name                = "vnet-integration-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  resource_group_name = "${var.networkingResourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
}

data "azurerm_subnet" "runners_subnet" {
  name                 = "snet-runners-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  resource_group_name  = "${var.networkingResourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  virtual_network_name = "vnet-integration-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
}

/**************************************************
New Resources
***************************************************/
// Container Registry
resource "azurerm_container_registry" "container_registry" {
  name                = "acr${var.resourceSuffix}${var.environment}${var.locationSuffix}"
  location            = var.location
  resource_group_name = local.fullResourceGroupName
  sku = "Basic"
}

// Container App Environment
resource "azurerm_container_app_environment" "container_app_environment" {
  // Change name to have 01 suffix
  name                       = "cae-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  location                   = var.location
  resource_group_name        = local.fullResourceGroupName
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.log_analytics_workspace.id
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    maximum_count         = 2
    minimum_count         = 1
  }
  infrastructure_subnet_id = data.azurerm_subnet.runners_subnet.id
}
