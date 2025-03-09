/**************************************************
Global Variables
***************************************************/
variable "location" {
  type        = string
  description = "The Azure location in which the deployment is happening"
}

variable "locationSuffix" {
  type        = string
  description = "The Azure location in which the deployment is happening"
}

variable "resourceSuffix" {
  type        = string
  description = "A suffix for naming"
}

variable "environment" {
  type        = string
  description = "Environment"
}

variable "environmentGroup" {
  type        = string
  description = "The environment group for cross environment shared resources such as networking components. e.g. nonprod, preprod, prod"
}

/**************************************************
Existing Resource Variables
***************************************************/
variable "networkResourceGroupName" {
  type        = string
  description = "The name of the networking resource group"
  default     = "rg-networking"
}

variable "sharedResourceGroupName" {
  type        = string
  description = "The name of the shared infra resource group"
  default     = "rg-shared"
}

/**************************************************
New Resource Variables
***************************************************/
variable "resourceGroupName" {
  type        = string
  description = "The name of the resource group to deploy to"
}

variable "functionAppInstance" {
  type        = string
  description = "The two digit instance identifier for the app if there are multiple"
  default     = ""
}

variable "functionAppPurpose" {
  type        = string
  description = "The purpose of the integrations serviced by the app, e.g. collect, cms, police, corrections"
}

variable "functionAppPurposeShort" {
  type        = string
  description = "The shortened purpose of the integrations serviced by the app, e.g. collect, cms, police, corrections"
  validation {
    condition     = length(var.functionAppPurposeShort) <= 9
    error_message = "functionAppPurposeShort must be 9 or fewer characters"
  }
}

variable "customAppSettings" {
  type        = map(string)
  description = "Terraform string map of additional app settings to add to the Function App"
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Terraform string map of tags to add to the Function App and associated resources"
  default     = {}
}

locals {
  fullResourceGroupName    = "${var.resourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  sharedResourceGroupName  = "${var.sharedResourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  networkResourceGroupName = "${var.networkResourceGroupName}-${var.resourceSuffix}-${var.environmentGroup}-${var.locationSuffix}"
  functionAppName          = "function-${var.functionAppPurpose}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}-${var.functionAppInstance}"
  storageAccountName       = "safa${var.functionAppPurposeShort}${var.environment}${var.locationSuffix}${var.functionAppInstance}"
  slotName                 = "deploy-slot"

  defaultAppSettings = {
    "WEBSITE_CONTENTOVERVNET"                      = "1"
    "WEBSITE_VNET_ROUTE_ALL"                       = "1"
    "WEBSITE_DNS_SERVER"                           = "168.63.129.16"
    "WEBSITE_CONTENTSHARE"                         = local.functionAppName
    "FUNCTIONS_WORKER_RUNTIME"                     = "dotnet-isolated"
    "APPINSIGHTS_INSTRUMENTATIONKEY"               = data.azurerm_application_insights.application_insights.instrumentation_key
    "WEBSITE_OVERRIDE_STICKY_DIAGNOSTICS_SETTINGS" = 0
  }

  slotAppSettings = {
    "WEBSITE_CONTENTOVERVNET"        = "1"
    "WEBSITE_VNET_ROUTE_ALL"         = "1"
    "WEBSITE_DNS_SERVER"             = "168.63.129.16"
    "WEBSITE_CONTENTSHARE"           = "${local.functionAppName}-${local.slotName}"
    "FUNCTIONS_WORKER_RUNTIME"       = "dotnet-isolated"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = data.azurerm_application_insights.application_insights.instrumentation_key
  }

  allAppSettings     = merge(local.defaultAppSettings, var.customAppSettings)
  allSlotAppSettings = merge(local.slotAppSettings, var.customAppSettings)
}