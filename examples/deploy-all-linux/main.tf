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
      allowSharedKeyAccess = true
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

resource "azurerm_storage_blob" "install_pwsh" {
  name                   = "Install-LinuxPowerShell.sh"
  storage_account_name   = azapi_resource.assets_sa.name
  storage_container_name = azapi_resource.assets_container.name
  type                   = "Block"
  source                 = "${path.module}/scripts/Install-LinuxPowerShell.sh"
}

resource "azurerm_storage_blob" "init_software" {
  name                   = "Initialize-LinuxSoftware.ps1"
  storage_account_name   = azapi_resource.assets_sa.name
  storage_container_name = azapi_resource.assets_container.name
  type                   = "Block"
  source                 = "${path.module}/scripts/Initialize-LinuxSoftware.ps1"
}

# --- Image builder pattern module ---

module "test" {
  source = "../../"

  compute_gallery_image_definition_name = "ubuntu-2204-devops"
  compute_gallery_image_definitions = {
    linux = {
      name    = "ubuntu-2204-devops"
      os_type = "Linux"
      identifier = {
        publisher = "devops"
        offer     = "devops_linux"
        sku       = "devops_linux_az"
      }
    }
  }
  image_template_image_source = {
    type      = "PlatformImage"
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  location  = azapi_resource.resource_group.location
  name      = "aib-${random_pet.name.id}"
  parent_id = azapi_resource.resource_group.id
  # Caller owns the build trigger so it fires after the assets RBAC propagates.
  build            = { enabled = false }
  enable_telemetry = var.enable_telemetry
  image_template_customization_steps = [
    {
      type      = "Shell"
      name      = "PowerShell Core installation"
      scriptUri = "${trimsuffix(azapi_resource.assets_sa.output.properties.primaryEndpoints.blob, "/")}/${azapi_resource.assets_container.name}/${azurerm_storage_blob.install_pwsh.name}"
    },
    {
      type        = "File"
      name        = "Download Initialize-LinuxSoftware.ps1"
      sourceUri   = "${trimsuffix(azapi_resource.assets_sa.output.properties.primaryEndpoints.blob, "/")}/${azapi_resource.assets_container.name}/${azurerm_storage_blob.init_software.name}"
      destination = "Initialize-LinuxSoftware.ps1"
    },
    {
      type   = "Shell"
      name   = "Software installation"
      inline = ["pwsh 'Initialize-LinuxSoftware.ps1'"]
    }
  ]
  vm_profile = {
    vm_size = "Standard_D2s_v3"
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
    create = "4h"
  }

  depends_on = [time_sleep.blob_rbac_propagation]
}
