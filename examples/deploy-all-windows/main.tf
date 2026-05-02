terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "azapi" {}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

data "azapi_client_config" "current" {}

resource "random_pet" "name" {
  length = 2
}

resource "random_string" "sa_suffix" {
  length  = 8
  lower   = true
  numeric = true
  special = false
  upper   = false
}

# --- Resource group ---

resource "azapi_resource" "resource_group" {
  location = "eastus"
  name     = "rg-${random_pet.name.id}"
  type     = "Microsoft.Resources/resourceGroups@2024-03-01"
  body     = {}
}

# --- Virtual network: build subnet + ACI-delegated subnet ---

resource "azapi_resource" "vnet" {
  location  = azapi_resource.resource_group.location
  name      = "vnet-${random_pet.name.id}"
  parent_id = azapi_resource.resource_group.id
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  body = {
    properties = {
      addressSpace = { addressPrefixes = ["10.10.0.0/16"] }
      subnets = [
        {
          name = "subnet-build"
          properties = {
            addressPrefix                     = "10.10.0.0/24"
            privateLinkServiceNetworkPolicies = "Disabled"
          }
        },
        {
          name = "subnet-aci"
          properties = {
            addressPrefix                     = "10.10.1.0/24"
            privateLinkServiceNetworkPolicies = "Disabled"
            delegations = [{
              name       = "aci"
              properties = { serviceName = "Microsoft.ContainerInstance/containerGroups" }
            }]
          }
        }
      ]
    }
  }
  response_export_values = ["properties.subnets"]
}

locals {
  aci_subnet_id = [
    for s in azapi_resource.vnet.output.properties.subnets : s.id if s.name == "subnet-aci"
  ][0]
  build_subnet_id = [
    for s in azapi_resource.vnet.output.properties.subnets : s.id if s.name == "subnet-build"
  ][0]
}

# --- Storage account, container, and uploaded scripts ---

resource "azapi_resource" "assets_sa" {
  location  = azapi_resource.resource_group.location
  name      = "stassets${random_string.sa_suffix.result}"
  parent_id = azapi_resource.resource_group.id
  type      = "Microsoft.Storage/storageAccounts@2024-01-01"
  body = {
    sku  = { name = "Standard_LRS" }
    kind = "StorageV2"
    properties = {
      allowSharedKeyAccess = false
      minimumTlsVersion    = "TLS1_2"
      networkAcls          = { defaultAction = "Allow", bypass = "AzureServices" }
    }
  }
  response_export_values = ["properties.primaryEndpoints.blob"]
}

resource "azapi_resource" "assets_container" {
  name      = "aibscripts"
  parent_id = "${azapi_resource.assets_sa.id}/blobServices/default"
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01"
  body = {
    properties = { publicAccess = "None" }
  }
}

# The caller needs Storage Blob Data Contributor on the SA to upload blobs via
# AAD auth (tenants commonly disable shared-key auth at the policy level).
resource "azapi_resource" "caller_blob_writer" {
  name      = uuidv5("dns", "${azapi_resource.assets_sa.id}-caller-blob-writer")
  parent_id = azapi_resource.assets_sa.id
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      principalId      = data.azapi_client_config.current.object_id
      roleDefinitionId = "/subscriptions/${data.azapi_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    }
  }
}

resource "time_sleep" "caller_blob_rbac_propagation" {
  create_duration = "60s"

  depends_on = [azapi_resource.caller_blob_writer]
}

resource "azurerm_storage_blob" "install_pwsh" {
  name                   = "Install-WindowsPowerShell.ps1"
  storage_account_name   = azapi_resource.assets_sa.name
  storage_container_name = azapi_resource.assets_container.name
  type                   = "Block"
  source                 = "${path.module}/scripts/Install-WindowsPowerShell.ps1"

  depends_on = [time_sleep.caller_blob_rbac_propagation]
}

resource "azurerm_storage_blob" "init_software" {
  name                   = "Initialize-WindowsSoftware.ps1"
  storage_account_name   = azapi_resource.assets_sa.name
  storage_container_name = azapi_resource.assets_container.name
  type                   = "Block"
  source                 = "${path.module}/scripts/Initialize-WindowsSoftware.ps1"

  depends_on = [time_sleep.caller_blob_rbac_propagation]
}

# --- Image builder pattern module ---

module "test" {
  source = "../../"

  compute_gallery_image_definition_name = "win11-24h2-devops"
  compute_gallery_image_definitions = {
    windows = {
      name    = "win11-24h2-devops"
      os_type = "Windows"
      identifier = {
        publisher = "devops"
        offer     = "devops_windows"
        sku       = "devops_windows_az"
      }
    }
  }
  image_template_image_source = {
    type      = "PlatformImage"
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-11"
    sku       = "win11-24h2-avd"
    version   = "latest"
  }
  location                 = azapi_resource.resource_group.location
  name                     = "aib-${random_pet.name.id}"
  parent_id                = azapi_resource.resource_group.id
  build                    = { enabled = false }
  build_timeout_in_minutes = 360
  enable_telemetry         = var.enable_telemetry
  image_template_customization_steps = [
    {
      type      = "PowerShell"
      name      = "PowerShell Core installation"
      scriptUri = "${trimsuffix(azapi_resource.assets_sa.output.properties.primaryEndpoints.blob, "/")}/${azapi_resource.assets_container.name}/${azurerm_storage_blob.install_pwsh.name}"
    },
    {
      type        = "File"
      name        = "Download Initialize-WindowsSoftware.ps1"
      sourceUri   = "${trimsuffix(azapi_resource.assets_sa.output.properties.primaryEndpoints.blob, "/")}/${azapi_resource.assets_container.name}/${azurerm_storage_blob.init_software.name}"
      destination = "C:\\Initialize-WindowsSoftware.ps1"
    },
    {
      type        = "PowerShell"
      name        = "Software installation"
      inline      = ["pwsh 'C:\\Initialize-WindowsSoftware.ps1'"]
      runElevated = true
      runAsSystem = true
    },
    {
      type           = "WindowsRestart"
      restartTimeout = "5m"
    },
    {
      type           = "WindowsUpdate"
      searchCriteria = "IsInstalled=0"
      updateLimit    = 40
    }
  ]
  vm_profile = {
    vm_size = "Standard_D4s_v3"
    vnet_config = {
      subnet_id                    = local.build_subnet_id
      container_instance_subnet_id = local.aci_subnet_id
    }
  }
}

# --- Grant the image builder identity read access to the script container,
#     wait for RBAC to propagate, then trigger the build. ---

resource "azapi_resource" "blob_reader_assignment" {
  name      = uuidv5("dns", "${azapi_resource.assets_container.id}-blob-reader")
  parent_id = azapi_resource.assets_container.id
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      principalId      = module.test.image_builder_identity_principal_id
      principalType    = "ServicePrincipal"
      roleDefinitionId = "/subscriptions/${data.azapi_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/2a2b9908-6ea1-4ae2-8e65-a410df84e7d1"
    }
  }
}

resource "time_sleep" "blob_rbac_propagation" {
  create_duration = "60s"

  depends_on = [azapi_resource.blob_reader_assignment]
}

resource "azapi_resource_action" "trigger_build" {
  action      = "run"
  method      = "POST"
  resource_id = module.test.image_template_id
  type        = "Microsoft.VirtualMachineImages/imageTemplates@2024-02-01"

  timeouts {
    create = "6h"
  }

  depends_on = [time_sleep.blob_rbac_propagation]
}
