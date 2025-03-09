/**************************************************
Existing Resources
***************************************************/
// NOTE: Need the VNET set up first before bootstrapping can start
data "azurerm_virtual_network" "mitchtest_vnet" {
  name                = "vnet-${var.resourceSuffix}-${var.environmentGroup}-${var.locationSuffix}"
  resource_group_name = "${var.networkingResourceGroupName}-${var.resourceSuffix}-${var.environmentGroup}-${var.locationSuffix}"
}

data "azurerm_subnet" "runners_subnet" {
  name                 = "snet-${var.resourceSuffix}-${var.environmentGroup}-runners-${var.locationSuffix}"
  resource_group_name  = "${var.networkingResourceGroupName}-${var.resourceSuffix}-${var.environmentGroup}-${var.locationSuffix}"
  virtual_network_name = data.azurerm_virtual_network.mitchtest_vnet.name
}

/**************************************************
New Resources
***************************************************/
// Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "log-${var.resourceSuffix}-deployment-${var.environmentGroup}-${var.locationSuffix}"
  location            = var.location
  resource_group_name = local.fullResourceGroupName
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.tags

  lifecycle {
    prevent_destroy = false
  }
}

// Azure Container Registry UAMI
resource "azurerm_user_assigned_identity" "acr_pull" {
  name                = "uami-acr-pull-${var.resourceSuffix}-${var.environmentGroup}-${var.locationSuffix}"
  resource_group_name = local.fullResourceGroupName
  location            = var.location

  tags = local.tags
}

// Container Registry
resource "azurerm_container_registry" "container_registry" {
  name                = "acr${var.resourceSuffix}${var.environmentGroup}${var.locationSuffix}"
  location            = var.location
  resource_group_name = local.fullResourceGroupName
  sku                 = "Basic"
  admin_enabled       = true

  tags = local.tags
}

// ACR Pull UAMI role assignment
resource "azurerm_role_assignment" "uami_role_assignment" {
  scope                = azurerm_container_registry.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.acr_pull.principal_id
}