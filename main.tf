data "azapi_client_config" "current" {}

# --- User-Assigned Identity for Image Builder ---
resource "azapi_resource" "image_builder_identity" {
  location               = var.location
  name                   = "msi-${var.name}"
  parent_id              = var.parent_id
  type                   = "Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30"
  create_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  delete_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  read_headers           = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  response_export_values = ["properties.principalId"]
  tags                   = var.tags
  update_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
}

# --- Azure Compute Gallery ---
resource "azapi_resource" "compute_gallery" {
  location  = var.location
  name      = local.compute_gallery_name
  parent_id = var.parent_id
  type      = "Microsoft.Compute/galleries@2024-03-03"
  body = {
    properties = {
      description = "Compute Gallery for ${var.name} image definitions"
    }
  }
  create_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  delete_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  read_headers           = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  response_export_values = []
  tags                   = var.tags
  update_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null

  dynamic "identity" {
    for_each = module.avm_interfaces.managed_identities_azapi != null ? [module.avm_interfaces.managed_identities_azapi] : []

    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }
}

# --- Gallery Image Definitions ---
resource "azapi_resource" "gallery_image_definition" {
  for_each = var.compute_gallery_image_definitions

  location  = var.location
  name      = each.value.name
  parent_id = azapi_resource.compute_gallery.id
  type      = "Microsoft.Compute/galleries/images@2024-03-03"
  body = {
    properties = {
      osType           = each.value.os_type
      osState          = each.value.os_state
      hyperVGeneration = each.value.hyper_v_generation
      architecture     = each.value.architecture
      description      = each.value.description
      identifier = {
        publisher = each.value.identifier.publisher
        offer     = each.value.identifier.offer
        sku       = each.value.identifier.sku
      }
    }
  }
  create_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  delete_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  read_headers           = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  response_export_values = []
  tags                   = var.tags
  update_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
}

# --- Staging Resource Group for AIB builds ---
resource "azapi_resource" "staging_resource_group" {
  count = var.staging_resource_group_name != null ? 1 : 0

  location               = var.location
  name                   = var.staging_resource_group_name
  parent_id              = data.azapi_client_config.current.subscription_resource_id
  type                   = "Microsoft.Resources/resourceGroups@2024-03-01"
  body                   = {}
  create_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  delete_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  read_headers           = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  response_export_values = []
  tags                   = var.tags
  update_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null

  lifecycle {
    ignore_changes = [tags]
  }
}

# --- RBAC: Identity -> Staging RG (Contributor) ---
# Deterministic UUIDv5 keyed on scope + principal + role to survive state loss / re-import.
resource "azapi_resource" "staging_rg_role_assignment" {
  count = var.staging_resource_group_name != null ? 1 : 0

  name      = uuidv5("oid", "${azapi_resource.staging_resource_group[0].id}-${azapi_resource.image_builder_identity.output.properties.principalId}-b24988ac-6180-42a0-ab88-20f7382dd24c")
  parent_id = azapi_resource.staging_resource_group[0].id
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      principalId      = azapi_resource.image_builder_identity.output.properties.principalId
      roleDefinitionId = "${data.azapi_client_config.current.subscription_resource_id}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
      principalType    = "ServicePrincipal"
    }
  }
  create_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  delete_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  read_headers           = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  response_export_values = []
  update_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
}

# --- RBAC: Identity -> Gallery (Contributor) ---
resource "azapi_resource" "gallery_role_assignment" {
  name      = uuidv5("oid", "${azapi_resource.compute_gallery.id}-${azapi_resource.image_builder_identity.output.properties.principalId}-b24988ac-6180-42a0-ab88-20f7382dd24c")
  parent_id = azapi_resource.compute_gallery.id
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      principalId      = azapi_resource.image_builder_identity.output.properties.principalId
      roleDefinitionId = "${data.azapi_client_config.current.subscription_resource_id}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
      principalType    = "ServicePrincipal"
    }
  }
  create_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  delete_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  read_headers           = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  response_export_values = []
  update_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
}

# --- RBAC: Identity -> VNet (Network Contributor), required for private builds ---
resource "azapi_resource" "vnet_role_assignment" {
  count = var.vm_profile.vnet_config != null ? 1 : 0

  name      = uuidv5("oid", "${local.vnet_id}-${azapi_resource.image_builder_identity.output.properties.principalId}-4d97b98b-1d4f-4787-a291-c67834d212e7")
  parent_id = local.vnet_id
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      principalId      = azapi_resource.image_builder_identity.output.properties.principalId
      roleDefinitionId = "${data.azapi_client_config.current.subscription_resource_id}/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
      principalType    = "ServicePrincipal"
    }
  }
  create_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  delete_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  read_headers           = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  response_export_values = []
  update_headers         = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
}

# --- RBAC propagation delay ---
resource "time_sleep" "rbac_propagation" {
  create_duration = "${var.rbac_propagation_delay_seconds}s"

  depends_on = [
    azapi_resource.gallery_role_assignment,
    azapi_resource.staging_rg_role_assignment,
    azapi_resource.vnet_role_assignment,
  ]
}

# --- Image Template ---
resource "azapi_resource" "image_template" {
  location  = var.location
  name      = local.image_template_name
  parent_id = var.parent_id
  type      = "Microsoft.VirtualMachineImages/imageTemplates@2024-02-01"
  body = {
    properties = {
      for k, v in {
        source                = local.image_source
        distribute            = local.distribute
        customize             = var.image_template_customization_steps
        vmProfile             = local.vm_profile
        buildTimeoutInMinutes = var.build_timeout_in_minutes
        optimize              = var.optimize_vm_boot ? { vmBoot = { state = "Enabled" } } : null
        stagingResourceGroup  = var.staging_resource_group_name != null ? azapi_resource.staging_resource_group[0].id : null
      } : k => v if v != null
    }
  }
  create_headers            = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  delete_headers            = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  read_headers              = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  response_export_values    = []
  schema_validation_enabled = false
  tags                      = var.tags
  update_headers            = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null

  identity {
    type         = "UserAssigned"
    identity_ids = [azapi_resource.image_builder_identity.id]
  }
  timeouts {
    create = "30m"
    delete = "30m"
    update = "30m"
  }

  depends_on = [
    time_sleep.rbac_propagation,
    azapi_resource.gallery_image_definition,
    azapi_resource.staging_rg_role_assignment,
    azapi_resource.vnet_role_assignment,
  ]

  lifecycle {
    precondition {
      condition     = anytrue([for k, v in var.compute_gallery_image_definitions : v.name == var.compute_gallery_image_definition_name || k == var.compute_gallery_image_definition_name])
      error_message = "compute_gallery_image_definition_name must match a key or the .name of an entry in compute_gallery_image_definitions."
    }
  }
}

resource "terraform_data" "build_trigger" {
  count = var.build.enabled ? 1 : 0

  input = var.build.trigger_id
}

resource "azapi_resource_action" "trigger_build" {
  count = var.build.enabled ? 1 : 0

  action      = "run"
  resource_id = azapi_resource.image_template.id
  type        = "Microsoft.VirtualMachineImages/imageTemplates@2024-02-01"

  timeouts {
    create = "4h"
  }

  depends_on = [azapi_resource.image_template]

  lifecycle {
    replace_triggered_by = [terraform_data.build_trigger[0]]
  }
}

resource "azapi_resource_action" "delete_gallery_image_version" {
  for_each = local.gallery_image_version_cleanup_targets

  action      = "versions/${var.build.gallery_image_version_name}"
  method      = "DELETE"
  resource_id = each.value.gallery_image_id
  type        = "Microsoft.Compute/galleries/images@2024-03-03"
  when        = "destroy"

  depends_on = [
    azapi_resource.gallery_image_definition,
    azapi_resource_action.trigger_build,
  ]
}
