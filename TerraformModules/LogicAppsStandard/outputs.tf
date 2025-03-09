output "logicapp_id" {
  description = "Specifies the resource id of the logic app."
  value       = azurerm_logic_app_standard.logicapp_standard.id
}

output "logicapp_principal_id" {
  description = "Specifies the resource id of the logic app."
  value       = azurerm_logic_app_standard.logicapp_standard.identity.0.principal_id
}