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

module "test" {
  source = "../../"

  compute_gallery_image_definition_name = "ubuntu-2404-custom"
  compute_gallery_image_definitions = {
    linux = {
      name    = "ubuntu-2404-custom"
      os_type = "Linux"
      identifier = {
        publisher = "MyOrg"
        offer     = "Ubuntu"
        sku       = "24.04-LTS-Custom"
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
  location                 = azapi_resource.resource_group.location
  name                     = "aib-${random_pet.name.id}"
  parent_id                = azapi_resource.resource_group.id
  build_timeout_in_minutes = 120
  enable_telemetry         = var.enable_telemetry
  image_template_customization_steps = [
    {
      type   = "Shell"
      name   = "install-packages"
      inline = ["sudo apt-get update", "sudo apt-get install -y nginx curl jq"]
    },
    {
      type   = "Shell"
      name   = "create-marker-file"
      inline = ["echo 'Built by Azure Image Builder' | sudo tee /opt/aib-marker.txt"]
    }
  ]
  vm_profile = {
    vm_size         = "Standard_D2s_v3"
    os_disk_size_gb = 64
  }
}
