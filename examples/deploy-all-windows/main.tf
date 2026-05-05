terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azapi" {}

resource "random_pet" "name" {
  length = 2
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

# --- Image builder pattern module ---

module "test" {
  source = "../../"

  compute_gallery_image_definition_name = "windows-2022-devops"
  compute_gallery_image_definitions = {
    windows = {
      name    = "windows-2022-devops"
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
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
  location                 = azapi_resource.resource_group.location
  name                     = "aib-${random_pet.name.id}"
  parent_id                = azapi_resource.resource_group.id
  build                    = { enabled = true }
  build_timeout_in_minutes = 360
  enable_telemetry         = var.enable_telemetry
  image_template_customization_steps = [
    {
      type = "PowerShell"
      name = "Marker file"
      inline = [
        "Set-Content -Path 'C:\\aib-marker.txt' -Value \"Built by Azure Image Builder at $(Get-Date -Format o)\"",
        "Get-Content -Path 'C:\\aib-marker.txt'",
      ]
      runElevated = true
      runAsSystem = true
    },
    {
      type           = "WindowsRestart"
      restartTimeout = "5m"
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
