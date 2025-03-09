/**************************************************
Existing Resources
***************************************************/
data "azurerm_api_management" "apim" {
  name                = "apim-${var.resourceSuffix}-${var.environment}-${var.locationSuffix}"
  resource_group_name = local.sharedResourceGroupName
}

data "azapi_resource" "apim_logger" {
  name                   = "apim-logger"
  parent_id              = data.azurerm_api_management.apim.id
  type                   = "Microsoft.ApiManagement/service/loggers@2022-08-01"
  response_export_values = ["*"]
}

data "azurerm_api_management_api_version_set" "api_versionset" {
  name                = var.apiName
  resource_group_name = local.sharedResourceGroupName
  api_management_name = data.azurerm_api_management.apim.name
}

data "azurerm_api_management_product" "apim_products" {
  for_each = toset(var.apiProductIds)

  product_id          = each.value
  resource_group_name = local.sharedResourceGroupName
  api_management_name = data.azurerm_api_management.apim.name
}

/**************************************************
Logic App Workflow backend url lookups
***************************************************/
# Fetch Logic Apps
data "azurerm_logic_app_standard" "logic_apps" {
  for_each            = var.logicAppBackends
  name                = each.key
  resource_group_name = each.value.resource_group_name
}

# Fetch Workflows
data "azapi_resource" "workflows" {
  for_each = local.workflows_map

  type                   = "Microsoft.Web/sites/workflows@2022-03-01"
  name                   = each.value.workflow_name
  parent_id              = data.azurerm_logic_app_standard.logic_apps[each.value.logic_app_name].id
  response_export_values = ["*"]
}

# Fetch Workflow Triggers
data "azapi_resource" "workflow_triggers" {
  for_each = local.workflows_map

  type                   = "Microsoft.Web/sites/hostruntime/webhooks/api/workflows/triggers@2022-09-01"
  name                   = "When_a_HTTP_request_is_received"
  parent_id              = "${data.azurerm_logic_app_standard.logic_apps[each.value.logic_app_name].id}/hostruntime/runtime/webhooks/workflow/api/management/workflows/${each.value.workflow_name}"
  response_export_values = ["*"]
}

# Get Workflow Trigger URLs
data "azapi_resource_action" "workflow_trigger_urls" {
  for_each = local.workflows_map

  type                   = "Microsoft.Web/sites/hostruntime/webhooks/api/workflows/triggers@2022-09-01"
  resource_id            = data.azapi_resource.workflow_triggers[each.key].id
  action                 = "listCallbackUrl"
  response_export_values = ["*"]
}
/**************************************************
Function App Function backend url lookups
***************************************************/
# Fetch Function Apps
data "azurerm_windows_function_app" "function_apps" {
  for_each            = local.functions_map
  name                = each.value.function_app_name
  resource_group_name = each.value.resource_group_name
}

# Get the function keys for the app
resource "azapi_resource_action" "function_keys" {
  for_each = local.functions_map

  type        = "Microsoft.Web/sites/functions@2024-04-01"
  resource_id = "${data.azurerm_windows_function_app.function_apps[each.key].id}/functions/${each.value.function_root_name}"
  action      = "listkeys"
  method      = "POST"

  response_export_values = ["default"]
}

/**************************************************
New Resources
***************************************************/
# Named values for signature keys
resource "azurerm_api_management_named_value" "api_workflow_signatures" {
  for_each = local.workflows_map

  name                = "${each.value.workflow_name}-signature"
  display_name        = "${each.value.workflow_name}-signature"
  resource_group_name = local.fullResourceGroupName
  api_management_name = data.azurerm_api_management.apim.name
  secret              = true

  value = jsondecode(data.azapi_resource_action.workflow_trigger_urls[each.key].output).queries.sig
}

# API Management Logic App Workflow Backends
resource "azurerm_api_management_backend" "api_workflow_backends" {
  for_each = local.workflows_map

  name                = "${each.value.workflow_name}"
  resource_group_name = local.fullResourceGroupName
  api_management_name = data.azurerm_api_management.apim.name
  protocol            = "http"
  url                 = jsondecode(data.azapi_resource_action.workflow_trigger_urls[each.key].output).basePath

  credentials {
    query = {
      "api-version" = jsondecode(data.azapi_resource_action.workflow_trigger_urls[each.key].output).queries.api-version
      "sig"         = "{{${azurerm_api_management_named_value.api_workflow_signatures[each.key].name}}}"
      "sp"          = jsondecode(data.azapi_resource_action.workflow_trigger_urls[each.key].output).queries.sp
      "sv"          = jsondecode(data.azapi_resource_action.workflow_trigger_urls[each.key].output).queries.sv
    }
  }

  depends_on = [azurerm_api_management_named_value.api_workflow_signatures]
}

# Named values for function keys
resource "azurerm_api_management_named_value" "api_func_signatures" {
  for_each = local.functions_map

  name                = "${each.value.function_name}-key"
  display_name        = "${each.value.function_name}-key"
  resource_group_name = local.fullResourceGroupName
  api_management_name = data.azurerm_api_management.apim.name
  secret              = true

  value = azapi_resource_action.function_keys[each.key].output.default
}

# API Management Function App Function Backends
resource "azurerm_api_management_backend" "api_func_backends" {
  for_each = local.functions_map

  name                = "${each.value.function_name}"
  resource_group_name = local.fullResourceGroupName
  api_management_name = data.azurerm_api_management.apim.name
  protocol            = "http"
  url                 = "https://${data.azurerm_windows_function_app.function_apps[each.key].default_hostname}/api/${each.value.function_root_name}"

  credentials {
    header = {
      "x-functions-key" = "{{${azurerm_api_management_named_value.api_func_signatures[each.key].name}}}"
    }
  }

  depends_on = [azurerm_api_management_named_value.api_func_signatures]
}

# API deployed from OpenAPI spec
resource "azurerm_api_management_api" "api" {
  name                = var.apiName
  display_name        = var.apiName
  resource_group_name = local.fullResourceGroupName
  api_management_name = data.azurerm_api_management.apim.name
  revision            = var.apiRevision
  protocols           = ["https"]
  path                = var.apiPath
  version_set_id      = data.azurerm_api_management_api_version_set.api_versionset.id
  version             = var.apiVersion

  subscription_key_parameter_names {
    header = "apiKey"
    query  = "apiKey"
  }

  import {
    content_format = "openapi"
    content_value  = var.apiSpecContent
  }

  depends_on = [azurerm_api_management_backend.api_workflow_backends]
}

# API logging and sampling, overrides logging settings for root APIM
# May want some additional inputs to log request/response payloads
resource "azurerm_api_management_api_diagnostic" "api_logging" {
  identifier               = "applicationinsights"
  resource_group_name      = local.fullResourceGroupName
  api_management_name      = data.azurerm_api_management.apim.name
  api_management_logger_id = data.azapi_resource.apim_logger.id
  api_name                 = azurerm_api_management_api.api.name

  http_correlation_protocol = "W3C"
  sampling_percentage       = var.apiSamplingRate
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"

  depends_on = [azurerm_api_management_api.api]
}

# Link API to Products
resource "azurerm_api_management_product_api" "api_product_link" {
  for_each = toset(var.apiProductIds)

  api_name            = azurerm_api_management_api.api.name
  api_management_name = data.azurerm_api_management.apim.name
  product_id          = each.value
  resource_group_name = local.fullResourceGroupName

  depends_on = [azurerm_api_management_api.api]
}

# Apply policy XML files to API operations by operationId
resource "azurerm_api_management_api_operation_policy" "operation_policy" {
  for_each = var.operationPolicies

  api_name            = azurerm_api_management_api.api.name
  operation_id        = each.key
  api_management_name = data.azurerm_api_management.apim.name
  resource_group_name = local.fullResourceGroupName
  xml_content         = each.value

  depends_on = [ 
    azurerm_api_management_api.api,
    azurerm_api_management_backend.api_workflow_backends,
    azurerm_api_management_backend.api_func_backends
  ]
}

# Alert for 5xx status codes returned by API
resource "azurerm_monitor_metric_alert" "api_failed_requests" {
  name                = "${var.apiName}-${var.apiVersion}-failed-requests"
  resource_group_name = local.fullResourceGroupName
  scopes              = [data.azurerm_api_management.apim.id]
  description         = "Alert for failed requests in ${var.apiName}-${var.apiVersion}"
  severity            = 1
  frequency           = "PT15M"
  window_size         = "PT30M"
  enabled             = true
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.ApiManagement/service"
    metric_name      = "Requests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 1

    dimension {
      name     = "BackendResponseCodeCategory"
      operator = "Include"
      values   = ["5xx"]
    }

    dimension {
      name     = "ApiId"
      operator = "Include"
      values   = ["${var.apiName}"]
    }
  }

  depends_on = [ azurerm_api_management_api.api ]
}