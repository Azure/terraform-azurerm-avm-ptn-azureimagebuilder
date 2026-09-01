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

  mock_resource "azapi_resource_action" {
    defaults = {
      id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.VirtualMachineImages/imageTemplates/it-test/run"
      output = {}
    }
  }

  mock_data "azapi_resource" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-existing/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-existing"
      name     = "uai-existing"
      location = "eastus"
      output = {
        properties = {
          principalId = "00000000-0000-0000-0000-000000000003"
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
    condition     = try(azapi_resource.gallery_image_definition["linux"].body.properties.features, null) == null
    error_message = "Gallery image features should be omitted when security_type is not set."
  }

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

  assert {
    condition     = azapi_resource.image_template.body.properties.distribute[0].excludeFromLatest == false
    error_message = "The default SharedImage distribution should preserve excludeFromLatest."
  }
}

run "vhd_distribution_with_uri_is_serialized" {
  command = apply

  variables {
    image_template_distribute = [
      {
        artifact_tags = {
          environment = "test"
        }
        run_output_name = "vhd-output"
        type            = "VHD"
        uri             = "https://example.blob.core.windows.net/images/example.vhd"
      }
    ]
  }

  assert {
    condition     = azapi_resource.image_template.body.properties.distribute[0].type == "VHD"
    error_message = "The VHD distribution type should be serialized."
  }

  assert {
    condition     = azapi_resource.image_template.body.properties.distribute[0].runOutputName == "vhd-output"
    error_message = "The VHD run output name should be serialized."
  }

  assert {
    condition     = azapi_resource.image_template.body.properties.distribute[0].uri == "https://example.blob.core.windows.net/images/example.vhd"
    error_message = "The VHD destination URI should be serialized."
  }

  assert {
    condition     = azapi_resource.image_template.body.properties.distribute[0].artifactTags.environment == "test"
    error_message = "The VHD artifact tags should be serialized."
  }

  assert {
    condition     = try(azapi_resource.image_template.body.properties.distribute[0].excludeFromLatest, null) == null
    error_message = "SharedImage-only excludeFromLatest must be omitted from VHD distributions."
  }
}

run "vhd_distribution_without_uri_uses_staging_output" {
  command = apply

  variables {
    image_template_distribute = [
      {
        run_output_name = "staging-vhd-output"
        type            = "VHD"
      }
    ]
  }

  assert {
    condition     = azapi_resource.image_template.body.properties.distribute[0].type == "VHD"
    error_message = "The VHD distribution type should be serialized without an explicit URI."
  }

  assert {
    condition     = try(azapi_resource.image_template.body.properties.distribute[0].uri, null) == null
    error_message = "The VHD URI should be omitted when the staging output is requested."
  }
}

run "shared_image_and_vhd_distributions_are_serialized_together" {
  command = apply

  variables {
    image_template_distribute = [
      {
        exclude_from_latest = true
        run_output_name     = "gallery-output"
        target_regions = [
          {
            name = "eastus"
          }
        ]
        type = "SharedImage"
        versioning = {
          major  = 2
          scheme = "Latest"
        }
      },
      {
        run_output_name = "vhd-output"
        type            = "VHD"
        uri             = "https://example.blob.core.windows.net/images/example.vhd"
      }
    ]
  }

  assert {
    condition     = length(azapi_resource.image_template.body.properties.distribute) == 2
    error_message = "Both SharedImage and VHD distributions should be serialized."
  }

  assert {
    condition     = azapi_resource.image_template.body.properties.distribute[0].excludeFromLatest == true
    error_message = "SharedImage excludeFromLatest should preserve an explicit true value."
  }

  assert {
    condition     = azapi_resource.image_template.body.properties.distribute[0].versioning.scheme == "Latest" && azapi_resource.image_template.body.properties.distribute[0].versioning.major == 2
    error_message = "SharedImage versioning should be serialized in a mixed distribution list."
  }

  assert {
    condition     = try(azapi_resource.image_template.body.properties.distribute[0].uri, null) == null
    error_message = "VHD-only uri must be omitted from SharedImage distributions."
  }

  assert {
    condition     = azapi_resource.image_template.body.properties.distribute[1].uri == "https://example.blob.core.windows.net/images/example.vhd"
    error_message = "The VHD URI should be serialized in a mixed distribution list."
  }

  assert {
    condition     = try(azapi_resource.image_template.body.properties.distribute[1].excludeFromLatest, null) == null
    error_message = "SharedImage-only excludeFromLatest must be omitted from the VHD distribution."
  }
}

run "managed_image_distribution_omits_shared_image_fields" {
  command = apply

  variables {
    image_template_distribute = [
      {
        image_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-images/providers/Microsoft.Compute/images/example"
        location        = "eastus"
        run_output_name = "managed-output"
        type            = "ManagedImage"
      }
    ]
  }

  assert {
    condition     = azapi_resource.image_template.body.properties.distribute[0].imageId == var.image_template_distribute[0].image_id
    error_message = "The managed image ID should be serialized."
  }

  assert {
    condition     = try(azapi_resource.image_template.body.properties.distribute[0].excludeFromLatest, null) == null
    error_message = "SharedImage-only excludeFromLatest must be omitted from ManagedImage distributions."
  }
}

run "invalid_distribution_type_rejected" {
  command = plan

  variables {
    image_template_distribute = [
      {
        run_output_name = "invalid-output"
        type            = "Invalid"
      }
    ]
  }

  expect_failures = [
    var.image_template_distribute,
  ]
}

run "vhd_distribution_rejects_non_https_uri" {
  command = plan

  variables {
    image_template_distribute = [
      {
        run_output_name = "insecure-vhd-output"
        type            = "VHD"
        uri             = "http://example.blob.core.windows.net/images/example.vhd"
      }
    ]
  }

  expect_failures = [
    var.image_template_distribute,
  ]
}

run "non_vhd_distribution_rejects_uri" {
  command = plan

  variables {
    image_template_distribute = [
      {
        run_output_name = "gallery-output"
        type            = "SharedImage"
        uri             = "https://example.blob.core.windows.net/images/example.vhd"
      }
    ]
  }

  expect_failures = [
    var.image_template_distribute,
  ]
}

run "gallery_image_security_types_are_serialized" {
  command = apply

  variables {
    compute_gallery_image_definition_name = "trusted-launch"
    compute_gallery_image_definitions = {
      trusted_launch = {
        name          = "trusted-launch"
        os_type       = "Linux"
        security_type = "TrustedLaunchSupported"
        identifier = {
          publisher = "TestOrg"
          offer     = "Ubuntu"
          sku       = "trusted-launch"
        }
      }
      confidential_vm = {
        name          = "confidential-vm"
        os_type       = "Linux"
        security_type = "ConfidentialVmSupported"
        identifier = {
          publisher = "TestOrg"
          offer     = "Ubuntu"
          sku       = "confidential-vm"
        }
      }
      trusted_launch_and_confidential_vm = {
        name          = "trusted-launch-and-confidential-vm"
        os_type       = "Linux"
        security_type = "TrustedLaunchAndConfidentialVmSupported"
        identifier = {
          publisher = "TestOrg"
          offer     = "Ubuntu"
          sku       = "trusted-launch-and-confidential-vm"
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.gallery_image_definition["trusted_launch"].body.properties.features == [{ name = "SecurityType", value = "TrustedLaunchSupported" }]
    error_message = "TrustedLaunchSupported should be serialized as the gallery image SecurityType feature."
  }

  assert {
    condition     = azapi_resource.gallery_image_definition["confidential_vm"].body.properties.features == [{ name = "SecurityType", value = "ConfidentialVmSupported" }]
    error_message = "ConfidentialVmSupported should be serialized as the gallery image SecurityType feature."
  }

  assert {
    condition     = azapi_resource.gallery_image_definition["trusted_launch_and_confidential_vm"].body.properties.features == [{ name = "SecurityType", value = "TrustedLaunchAndConfidentialVmSupported" }]
    error_message = "TrustedLaunchAndConfidentialVmSupported should be serialized as the gallery image SecurityType feature."
  }
}

run "invalid_gallery_image_security_type_rejected" {
  command = plan

  variables {
    compute_gallery_image_definitions = {
      linux = {
        name          = "ubuntu-2404"
        os_type       = "Linux"
        security_type = "InvalidSecurityType"
        identifier = {
          publisher = "TestOrg"
          offer     = "Ubuntu"
          sku       = "24.04-LTS"
        }
      }
    }
  }

  expect_failures = [
    var.compute_gallery_image_definitions,
  ]
}

run "gallery_image_security_type_requires_generation_two" {
  command = plan

  variables {
    compute_gallery_image_definitions = {
      linux = {
        name               = "ubuntu-2404"
        os_type            = "Linux"
        hyper_v_generation = "V1"
        security_type      = "TrustedLaunchSupported"
        identifier = {
          publisher = "TestOrg"
          offer     = "Ubuntu"
          sku       = "24.04-LTS"
        }
      }
    }
  }

  expect_failures = [
    var.compute_gallery_image_definitions,
  ]
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

  assert {
    condition     = length(terraform_data.build_trigger) == 0
    error_message = "Build trigger data should not be created by default."
  }

  assert {
    condition     = length(azapi_resource_action.delete_gallery_image_version) == 0
    error_message = "Gallery image version cleanup should not be created when builds are disabled."
  }
}

run "build_enabled_triggers_build_and_cleanup" {
  command = apply

  variables {
    build = { enabled = true }
  }

  assert {
    condition     = length(terraform_data.build_trigger) == 1
    error_message = "Build trigger data should be created when builds are enabled."
  }

  assert {
    condition     = length(azapi_resource_action.trigger_build) == 1
    error_message = "Build should be triggered when build.enabled is true."
  }

  assert {
    condition     = length(azapi_resource_action.delete_gallery_image_version) == 1
    error_message = "Shared Image Gallery version cleanup should be created for module-triggered builds."
  }
}

run "build_cleanup_can_be_disabled" {
  command = apply

  variables {
    build = {
      cleanup_gallery_image_version_on_destroy = false
      enabled                                  = true
    }
  }

  assert {
    condition     = length(azapi_resource_action.trigger_build) == 1
    error_message = "Build should still be triggered when cleanup is disabled."
  }

  assert {
    condition     = length(azapi_resource_action.delete_gallery_image_version) == 0
    error_message = "Gallery image version cleanup should not be created when cleanup is disabled."
  }
}

run "optimize_vm_boot_omitted_by_default" {
  command = apply

  assert {
    condition     = try(azapi_resource.image_template.body.properties.optimize, null) == null
    error_message = "VM boot optimization should be omitted by default."
  }
}

run "optimize_vm_boot_enabled_sets_body" {
  command = apply

  variables {
    optimize_vm_boot = true
  }

  assert {
    condition     = azapi_resource.image_template.body.properties.optimize.vmBoot.state == "Enabled"
    error_message = "VM boot optimization should be enabled when optimize_vm_boot is true."
  }
}

run "gallery_rbac_uses_contributor" {
  command = apply

  assert {
    condition     = endswith(azapi_resource.gallery_role_assignment.body.properties.roleDefinitionId, "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c")
    error_message = "Gallery RBAC should use the Contributor role definition."
  }
}

run "lock_creation" {
  command = apply

  variables {
    lock = {
      kind = "CanNotDelete"
      name = "test-lock"
    }
  }

  assert {
    condition     = length(azapi_resource.lock) == 1
    error_message = "Lock should be created when lock is specified."
  }
}

run "no_lock_by_default" {
  command = apply

  assert {
    condition     = length(azapi_resource.lock) == 0
    error_message = "Lock should not be created when lock is null."
  }
}

run "staging_rg_not_created_by_default" {
  command = apply

  assert {
    condition     = length(azapi_resource.staging_resource_group) == 0
    error_message = "Staging RG should not be created when staging_resource_group_name is null."
  }
}

run "staging_rg_created_when_set" {
  command = apply

  variables {
    staging_resource_group_name = "rg-test-staging"
  }

  assert {
    condition     = length(azapi_resource.staging_resource_group) == 1
    error_message = "Staging RG should be created when staging_resource_group_name is set."
  }

  assert {
    condition     = length(azapi_resource.staging_rg_role_assignment) == 1
    error_message = "Staging RG RBAC should be created when staging_resource_group_name is set."
  }
}

run "byo_image_builder_identity_used_when_set" {
  command = apply

  variables {
    image_builder_identity_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-existing/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-existing"
  }

  assert {
    condition     = length(azapi_resource.image_builder_identity) == 0
    error_message = "The module should not create an image builder identity when image_builder_identity_resource_id is set."
  }

  assert {
    condition     = output.image_builder_identity_id == var.image_builder_identity_resource_id
    error_message = "The image builder identity output should return the BYO identity resource ID."
  }

  assert {
    condition     = azapi_resource.gallery_role_assignment.body.properties.principalId == data.azapi_resource.image_builder_identity[0].output.properties.principalId
    error_message = "Gallery RBAC should target the BYO identity principal ID."
  }
}

run "byo_staging_rg_used_when_set" {
  command = apply

  variables {
    staging_resource_group_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-existing-staging"
  }

  assert {
    condition     = length(azapi_resource.staging_resource_group) == 0
    error_message = "The module should not create a staging resource group when staging_resource_group_resource_id is set."
  }

  assert {
    condition     = length(azapi_resource.staging_rg_role_assignment) == 1
    error_message = "The module should create RBAC for the BYO staging resource group."
  }

  assert {
    condition     = azapi_resource.staging_rg_role_assignment[0].parent_id == var.staging_resource_group_resource_id
    error_message = "Staging resource group RBAC should use the BYO resource group ID."
  }

  assert {
    condition     = azapi_resource.image_template.body.properties.stagingResourceGroup == var.staging_resource_group_resource_id
    error_message = "The image template should use the BYO staging resource group ID."
  }
}

run "staging_rg_name_and_id_rejected" {
  command = plan

  variables {
    staging_resource_group_name        = "rg-test-staging"
    staging_resource_group_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-existing-staging"
  }

  expect_failures = [
    var.staging_resource_group_name
  ]
}

run "timeouts_can_be_configured" {
  command = apply

  variables {
    build = { enabled = true }
    timeouts = {
      compute_gallery_delete = "32m"
      image_template_create  = "45m"
      image_template_delete  = "46m"
      image_template_update  = "47m"
      trigger_build_create   = "5h"
    }
  }

  assert {
    condition     = azapi_resource.compute_gallery.timeouts.delete == "32m"
    error_message = "Compute gallery delete timeout should be configurable."
  }

  assert {
    condition     = contains(azapi_resource.compute_gallery.retry.error_message_regex, "CannotDeleteResource")
    error_message = "Compute gallery delete should retry transient nested-resource conflicts."
  }

  assert {
    condition     = azapi_resource.image_template.timeouts.create == "45m"
    error_message = "Image template create timeout should be configurable."
  }

  assert {
    condition     = azapi_resource.image_template.timeouts.delete == "46m"
    error_message = "Image template delete timeout should be configurable."
  }

  assert {
    condition     = azapi_resource.image_template.timeouts.update == "47m"
    error_message = "Image template update timeout should be configurable."
  }

  assert {
    condition     = azapi_resource_action.trigger_build[0].timeouts.create == "5h"
    error_message = "Build trigger create timeout should be configurable."
  }
}

run "invalid_compute_gallery_name_rejected" {
  command = plan

  variables {
    compute_gallery_name = "gal-test"
  }

  expect_failures = [
    var.compute_gallery_name
  ]
}

run "invalid_platform_image_source_rejected" {
  command = plan

  variables {
    image_template_image_source = {
      type = "PlatformImage"
    }
  }

  expect_failures = [
    var.image_template_image_source
  ]
}

run "invalid_managed_image_source_rejected" {
  command = plan

  variables {
    image_template_image_source = {
      type = "ManagedImage"
    }
  }

  expect_failures = [
    var.image_template_image_source
  ]
}

run "invalid_shared_image_source_rejected" {
  command = plan

  variables {
    image_template_image_source = {
      type = "SharedImageVersion"
    }
  }

  expect_failures = [
    var.image_template_image_source
  ]
}
