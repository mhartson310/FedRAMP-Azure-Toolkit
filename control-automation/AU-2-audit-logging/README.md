# AU-2: Audit Events - Terraform Configuration
# Deploys centralized logging infrastructure for FedRAMP compliance

terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus2"
}

variable "log_retention_days" {
  description = "Log retention in days (FedRAMP minimum: 365)"
  type        = number
  default     = 365
  
  validation {
    condition     = var.log_retention_days >= 365
    error_message = "FedRAMP High requires minimum 1-year (365 days) log retention."
  }
}

variable "enable_sentinel" {
  description = "Enable Microsoft Sentinel"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    FedRAMP-Control = "AU-2"
    Compliance      = "Required"
    ManagedBy       = "Terraform"
  }
}

# Resource Group for Logging Infrastructure
resource "azurerm_resource_group" "logging" {
  name     = "rg-${var.environment}-${var.location}-logging"
  location = var.location
  tags     = var.common_tags
}

# Log Analytics Workspace (Central Logging)
resource "azurerm_log_analytics_workspace" "fedramp" {
  name                = "log-${var.environment}-${var.location}-fedramp"
  location            = var.location
  resource_group_name = azurerm_resource_group.logging.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = merge(var.common_tags, {
    Purpose = "FedRAMP Centralized Audit Logging"
  })
}

# Storage Account for Archive (Immutable Logs)
resource "azurerm_storage_account" "audit_archive" {
  name                     = "staudit${var.environment}${replace(var.location, "-", "")}"
  resource_group_name      = azurerm_resource_group.logging.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "GRS"  # Geo-redundant for compliance
  
  # Immutability for FedRAMP
  blob_properties {
    versioning_enabled = true
    
    container_delete_retention_policy {
      days = var.log_retention_days
    }
    
    delete_retention_policy {
      days = var.log_retention_days
    }
  }
  
  tags = merge(var.common_tags, {
    Purpose = "Audit Log Archive - Immutable"
  })
}

# Storage Container for Audit Logs
resource "azurerm_storage_container" "audit_logs" {
  name                  = "audit-logs"
  storage_account_name  = azurerm_storage_account.audit_archive.name
  container_access_type = "private"
}

# Microsoft Sentinel (SIEM)
resource "azurerm_log_analytics_solution" "sentinel" {
  count                 = var.enable_sentinel ? 1 : 0
  solution_name         = "SecurityInsights"
  location              = var.location
  resource_group_name   = azurerm_resource_group.logging.name
  workspace_resource_id = azurerm_log_analytics_workspace.fedramp.id
  workspace_name        = azurerm_log_analytics_workspace.fedramp.name
  
  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/SecurityInsights"
  }
  
  tags = var.common_tags
}

# Data Collection Rule (for VMs and resources)
resource "azurerm_monitor_data_collection_rule" "fedramp" {
  name                = "dcr-${var.environment}-fedramp-audit"
  location            = var.location
  resource_group_name = azurerm_resource_group.logging.name
  
  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.fedramp.id
      name                  = "fedramp-workspace"
    }
  }
  
  data_flow {
    streams      = ["Microsoft-Syslog", "Microsoft-Perf", "Microsoft-SecurityEvent"]
    destinations = ["fedramp-workspace"]
  }
  
  data_sources {
    syslog {
      facility_names = ["*"]
      log_levels     = ["*"]
      name           = "syslog-datasource"
    }
    
    performance_counter {
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers            = ["\\Processor(_Total)\\% Processor Time"]
      name                          = "perf-datasource"
    }
  }
  
  tags = var.common_tags
}

# Azure Policy Assignment - Enforce Diagnostic Settings
resource "azurerm_policy_assignment" "diagnostic_logging" {
  name                 = "fedramp-enforce-diagnostics"
  scope                = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.diagnostic_logging.id
  description          = "FedRAMP AU-2: Enforce diagnostic logging on all resources"
  display_name         = "FedRAMP - Require Diagnostic Logging"
  
  parameters = jsonencode({
    logAnalyticsWorkspaceId = {
      value = azurerm_log_analytics_workspace.fedramp.id
    }
    retentionDays = {
      value = var.log_retention_days
    }
  })
}

# Policy Definition - Diagnostic Logging
resource "azurerm_policy_definition" "diagnostic_logging" {
  name         = "fedramp-diagnostic-logging"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "FedRAMP AU-2: Diagnostic Logging Required"
  description  = "Enforces diagnostic logging for FedRAMP compliance"
  
  metadata = jsonencode({
    category = "FedRAMP"
    version  = "1.0.0"
  })
  
  parameters = jsonencode({
    logAnalyticsWorkspaceId = {
      type = "String"
      metadata = {
        displayName = "Log Analytics Workspace ID"
      }
    }
    retentionDays = {
      type = "Integer"
      defaultValue = 365
      metadata = {
        displayName = "Retention Days"
      }
    }
  })
  
  policy_rule = jsonencode({
    if = {
      anyOf = [
        { field = "type", equals = "Microsoft.Compute/virtualMachines" },
        { field = "type", equals = "Microsoft.Storage/storageAccounts" },
        { field = "type", equals = "Microsoft.KeyVault/vaults" },
        { field = "type", equals = "Microsoft.Sql/servers/databases" },
        { field = "type", equals = "Microsoft.Network/networkSecurityGroups" },
        { field = "type", equals = "Microsoft.Network/azureFirewalls" }
      ]
    }
    then = {
      effect = "deployIfNotExists"
      details = {
        type = "Microsoft.Insights/diagnosticSettings"
        roleDefinitionIds = [
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        ]
        deployment = {
          properties = {
            mode = "incremental"
            template = {
              "$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
              contentVersion = "1.0.0.0"
              parameters = {
                resourceName = { type = "string" }
                logAnalytics = { type = "string" }
                retention    = { type = "int" }
              }
              resources = [{
                type = "Microsoft.Insights/diagnosticSettings"
                apiVersion = "2021-05-01-preview"
                name = "fedramp-diagnostics"
                properties = {
                  workspaceId = "[parameters('logAnalytics')]"
                  logs = [{
                    category = "allLogs"
                    enabled  = true
                    retentionPolicy = {
                      enabled = true
                      days    = "[parameters('retention')]"
                    }
                  }]
                  metrics = [{
                    category = "AllMetrics"
                    enabled  = true
                    retentionPolicy = {
                      enabled = true
                      days    = "[parameters('retention')]"
                    }
                  }]
                }
              }]
            }
          }
        }
      }
    }
  })
}

# Data source for current subscription
data "azurerm_subscription" "current" {}

# Outputs
output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID"
  value       = azurerm_log_analytics_workspace.fedramp.id
}

output "log_analytics_workspace_name" {
  description = "Log Analytics Workspace Name"
  value       = azurerm_log_analytics_workspace.fedramp.name
}

output "storage_account_name" {
  description = "Audit archive storage account name"
  value       = azurerm_storage_account.audit_archive.name
}

output "sentinel_enabled" {
  description = "Microsoft Sentinel enabled"
  value       = var.enable_sentinel
}

output "log_retention_days" {
  description = "Log retention period (days)"
  value       = var.log_retention_days
}
