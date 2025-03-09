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
  default     = "rg-shared"
}

variable "tags" {
  type        = map(string)
  description = "Terraform string map of tags to add to the Function App and associated resources"
  default     = {}
}

variable "logicAppBackends" {
  description = "A map of Logic Apps, each with its resource group and workflow names to set up api backends for"
  type = map(object({
    resource_group_name = string
    workflows           = list(string)
  }))
}

variable "functionAppBackends" {
  description = "A map of Function Apps, each with its resource group and function names to set up api backends for"
  type = map(object({
    resource_group_name = string
    functions           = list(string)
  }))
}

variable "apiName" {
  description = "The name of the api, lower case with dashes instead of spaces e.g. api-test"
  type        = string
}

variable "apiSpecContent" {
  description = "The OpenAPI spec to create the API from. Will need to use file() command in TF file calling the module to get the spec conent to pass in here"
  type        = string
}

variable "apiRevision" {
  description = "The minor version of the API, should increment each time the spec is modified"
  type        = number
}

variable "apiVersion" {
  description = "The major version of the API, intended to be able to run in parallel as previous versions"
  type        = string
}

variable "apiPath" {
  description = "The api path value to put after the root domain"
  type        = string
}

variable "apiSamplingRate" {
  description = "The percentage of traffic to log for this API. Overrides the base APIM logging rules"
  type        = number
}

variable "apiProductIds" {
  description = "List of APIM product_id values to which the API should be linked."
  type        = list(string)
}

variable "operationPolicies" {
  description = "Map of operationIds and corresponding policy XML file paths"
  type        = map(string)
}

locals {
  fullResourceGroupName    = "${var.resourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  sharedResourceGroupName  = "${var.sharedResourceGroupName}-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  networkResourceGroupName = "${var.networkResourceGroupName}-${var.resourceSuffix}-${var.environmentGroup}-${var.locationSuffix}"

  workflows = flatten([
    for la_name, la_data in var.logicAppBackends : [
      for wf in la_data.workflows : {
        logic_app_name      = la_name
        resource_group_name = la_data.resource_group_name
        workflow_name       = wf
      }
    ]
  ])
  workflows_map = {
    for wf in local.workflows :
    "${wf.logic_app_name}.${wf.workflow_name}" => wf
  }

  /**
  * Should result in an object that looks like:
  * {
  *   "las-sandbox-mitchtest-aue-dev.wf-test" = {
  *     logic_app_name     = "las-sandbox-mitchtest-aue-dev"
  *     resource_group_name = "rg-sandbox-mitchtest-aue-dev"
  *     workflow_name      = "wf-test"
  *   },
  *   "las-sandbox-mitchtest-aue-dev.wf-sampleapi-backend" = {
  *     logic_app_name     = "las-sandbox-mitchtest-aue-dev"
  *     resource_group_name = "rg-sandbox-mitchtest-aue-dev"
  *     workflow_name      = "wf-sampleapi-backend"
  *   }
  * }
  */

  functions = flatten([
    for fa_name, fa_data in var.functionAppBackends : [
      for funcName in fa_data.functions : {
        function_app_name   = fa_name
        resource_group_name = fa_data.resource_group_name
        function_root_name  = funcName
        function_name       = "func-${lower(funcName)}"
      }
    ]
  ])
  functions_map = {
    for func in local.functions :
    "${func.function_app_name}.${func.function_name}" => func
  }
}