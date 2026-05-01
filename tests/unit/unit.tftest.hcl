mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/msi-test"
      name     = "it-test"
      location = "eastus"
      output = {
        properties = {
          principalId       = "00000000-0000-0000-0000-000000000002"
          provisioningState = "Succeeded"
        }
      }
    }
  }

  mock_data "azapi_client_config" {
    defaults = {
      subscription_id          = "00000000-0000-0000-0000-000000000000"
      subscription_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
      tenant_id                = "00000000-0000-0000-0000-000000000001"
    }
  }
}
mock_provider "modtm" {
  mock_data "modtm_module_source" {
    defaults = {
      module_source  = "registry.terraform.io/Azure/avm-ptn-azureimagebuilder/azurerm"
      module_version = "0.1.0"
    }
  }
}
mock_provider "random" {
  mock_resource "random_uuid" {
    defaults = {
      result = "00000000-0000-0000-0000-000000000000"
    }
  }
}
mock_provider "time" {}

variables {
  location         = "eastus"
  name             = "test-aib"
  parent_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
  enable_telemetry = true

  image_template_image_source = {
    type      = "PlatformImage"
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  compute_gallery_image_definitions = {
    linux = {
      name    = "ubuntu-2404"
      os_type = "Linux"
      identifier = {
        publisher = "TestOrg"
        offer     = "Ubuntu"
        sku       = "24.04-LTS"
      }
    }
  }

  compute_gallery_image_definition_name = "ubuntu-2404"
}

run "basic_aib_creation" {
  command = apply

  assert {
    condition     = output.image_template_id != ""
    error_message = "Image template ID should not be empty."
  }

  assert {
    condition     = output.compute_gallery_id != ""
    error_message = "Compute gallery ID should not be empty."
  }

  assert {
    condition     = output.image_builder_identity_id != ""
    error_message = "Image builder identity ID should not be empty."
  }
}

run "telemetry_enabled" {
  command = apply

  assert {
    condition     = length(modtm_telemetry.telemetry) == 1
    error_message = "Telemetry resource should be created when enable_telemetry is true."
  }
}

run "telemetry_disabled" {
  command = apply

  variables {
    enable_telemetry = false
  }

  assert {
    condition     = length(modtm_telemetry.telemetry) == 0
    error_message = "Telemetry resource should not be created when enable_telemetry is false."
  }
}

run "no_build_by_default" {
  command = apply

  assert {
    condition     = length(azapi_resource_action.trigger_build) == 0
    error_message = "Build should not be triggered by default."
  }
}
