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

variable "logicAppInstance" {
  type        = string
  description = "The two digit instance identifier for the app if there are multiple"
}

variable "logicAppPurpose" {
  type        = string
  description = "The purpose of the integrations serviced by the app, e.g. collect, cms, police, corrections"
}

variable "logicAppPurposeShort" {
  type        = string
  description = "The shortened purpose of the integrations serviced by the app, e.g. collect, cms, police, correc. Used in storage account naming"
  validation {
    condition     = length(var.logicAppPurposeShort) <= 9
    error_message = "logicAppPurposeShort must be 9 or fewer characters"
  }
}

variable "customAppSettings" {
  type        = map(string)
  description = "Terraform string map of additional app settings to add to the Logic App"
  default     = {}
}

variable "customIPRestrictions" {
  description = "List of IP restriction objects of additional rules to add to the Logic App"
  type = list(object({
    name                      = optional(string)
    ip_address                = optional(string)
    service_tag               = optional(string)
    virtual_network_subnet_id = optional(string)
    priority                  = optional(number)
    action                    = optional(string)
    headers = optional(list(object({
      x_azure_fdid      = optional(list(string))
      x_fd_health_probe = optional(list(string))
      x_forwarded_for   = optional(list(string))
      x_forwarded_host  = optional(list(string))
    })))
  }))
  default = []
}

variable "tags" {
  type        = map(string)
  description = "Terraform string map of tags to add to the Logic App and associated resources"
  default     = {}
}

locals {
  fullResourceGroupName    = "${var.resourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  sharedResourceGroupName  = "${var.sharedResourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  networkResourceGroupName = "${var.networkResourceGroupName}-${var.resourceSuffix}-${var.environmentGroup}-${var.locationSuffix}"
  logicAppName             = "logic-${var.logicAppPurpose}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}-${var.logicAppInstance}"
  storageAccountName       = "salas${var.logicAppPurposeShort}${var.environment}${var.locationSuffix}${var.logicAppInstance}"
  slotName                 = "deploy-slot"

  uuid          = "b464192d-6a9d-4629-8e07-c5eacdc7b473"
  appHostId     = replace(lower(uuidv5(local.uuid, "${local.logicAppName}")), "-", "")
  appSlotHostId = replace(lower(uuidv5(local.uuid, "${local.logicAppName}-${local.slotName}")), "-", "")

  defaultAppSettings = {
    "WEBSITE_DNS_SERVER"             = "168.63.129.16"
    "WEBSITE_CONTENTOVERVNET"        = "1"
    "WEBSITE_VNET_ROUTE_ALL"         = "1"
    "FUNCTIONS_WORKER_RUNTIME"       = "dotnet"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = data.azurerm_application_insights.application_insights.instrumentation_key
  }

  defaultIPRestrictions = [
    {
      name                      = "Azure Monitor Action Group"
      action                    = "Allow"
      priority                  = null
      virtual_network_subnet_id = null
      ip_address                = null
      service_tag               = "ActionGroup"
      headers                   = null
    },
    {
      name                      = "Runner Subnet"
      action                    = "Allow"
      priority                  = null
      virtual_network_subnet_id = data.azurerm_subnet.runner_subnet.id
      ip_address                = null
      service_tag               = null
      headers                   = null
    }
  ]

  allAppSettings    = merge(local.defaultAppSettings, var.customAppSettings)
  allIPRestrictions = concat(local.defaultIPRestrictions, var.customIPRestrictions)
}