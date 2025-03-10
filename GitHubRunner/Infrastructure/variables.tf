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
  type = string
}

/**************************************************
Existing Resource Variables
***************************************************/
variable "networkingResourceGroupName" {
  type        = string
  description = "The name of the networking resource group"
  default     = "rg-networking"
}

/**************************************************
New Resource Variables
***************************************************/
variable "resourceGroupName" {
  type        = string
  description = "The name of the resource group"
  default     = "rg-deploymentinfra"
}

locals {
  fullResourceGroupName = "${var.resourceGroupName}-${var.resourceSuffix}-${var.environmentGroup}-${var.locationSuffix}"
  tags = {
    "application-name"  = "Mitchtest DevOps"
    "environment"       = var.environmentGroup
    "owner"             = "mitch.abel@adaptiv.nz"
    "primary-support"   = ""
    "rc-code"           = ""
    "secondary-support" = "Adaptiv"
  }
}