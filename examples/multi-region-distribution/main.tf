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

resource "azapi_resource" "resource_group" {
  location               = "eastus"
  name                   = "rg-${random_pet.name.id}"
  type                   = "Microsoft.Resources/resourceGroups@2024-03-01"
  body                   = {}
  response_export_values = []
}

# This example demonstrates multi-region image distribution with custom
# replica counts and storage types per region.
module "test" {
  source = "../../"

  compute_gallery_image_definition_name = "ubuntu-2404-multi"
  compute_gallery_image_definitions = {
    linux = {
      name    = "ubuntu-2404-multi"
      os_type = "Linux"
      identifier = {
        publisher = "MyOrg"
        offer     = "Ubuntu"
        sku       = "24.04-LTS-MultiRegion"
      }
    }
  }
  image_template_image_source = {
    type      = "PlatformImage"
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  location         = azapi_resource.resource_group.location
  name             = "aib-${random_pet.name.id}"
  parent_id        = azapi_resource.resource_group.id
  enable_telemetry = var.enable_telemetry
  # Custom distribution with multiple regions
  image_template_distribute = [
    {
      type             = "SharedImage"
      run_output_name  = "multi-region-output"
      gallery_image_id = null # Will use default gallery image definition
      target_regions = [
        {
          name                 = "eastus"
          replica_count        = 2
          storage_account_type = "Standard_ZRS"
        },
        {
          name                 = "westus2"
          replica_count        = 1
          storage_account_type = "Standard_LRS"
        },
        {
          name                 = "westeurope"
          replica_count        = 1
          storage_account_type = "Standard_LRS"
        }
      ]
      artifact_tags = {
        environment = "production"
        managed_by  = "terraform"
      }
    }
  ]
}
