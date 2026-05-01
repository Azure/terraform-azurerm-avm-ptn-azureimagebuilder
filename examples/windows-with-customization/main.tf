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

  compute_gallery_image_definition_name = "win11-avd"
  compute_gallery_image_definitions = {
    windows = {
      name    = "win11-avd"
      os_type = "Windows"
      identifier = {
        publisher = "MyOrg"
        offer     = "Windows11"
        sku       = "24H2-AVD"
      }
    }
  }
  image_template_image_source = {
    type      = "PlatformImage"
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-avd"
    version   = "latest"
  }
  location                 = azapi_resource.resource_group.location
  name                     = "aib-${random_pet.name.id}"
  parent_id                = azapi_resource.resource_group.id
  build_timeout_in_minutes = 360
  enable_telemetry         = var.enable_telemetry
  image_template_customization_steps = [
    {
      type        = "PowerShell"
      name        = "install-features"
      inline      = ["Install-WindowsFeature -Name Web-Server"]
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
  }
}
