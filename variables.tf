# --- Image Template ---

# --- AVM interface variables ---

variable "compute_gallery_image_definition_name" {
  type        = string
  description = "The name of the image definition to publish the new image version to. Must match a key or name in `compute_gallery_image_definitions`."
  nullable    = false
}

variable "compute_gallery_image_definitions" {
  type = map(object({
    name               = string
    os_type            = string
    os_state           = optional(string, "Generalized")
    hyper_v_generation = optional(string, "V2")
    architecture       = optional(string, "x64")
    description        = optional(string, null)
    identifier = object({
      publisher = string
      offer     = string
      sku       = string
    })
  }))
  description = <<DESCRIPTION
A map of image definitions to create in the compute gallery. The map key is arbitrary.

- `name` - (Required) The name of the image definition.
- `os_type` - (Required) The OS type. Possible values: `Linux`, `Windows`.
- `os_state` - (Optional) Defaults to `Generalized`.
- `hyper_v_generation` - (Optional) Defaults to `V2`.
- `architecture` - (Optional) Defaults to `x64`. Possible values: `x64`, `Arm64`.
- `identifier` - (Required) The image identifier (publisher, offer, sku).
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for v in var.compute_gallery_image_definitions : contains(["Linux", "Windows"], v.os_type)])
    error_message = "Each compute_gallery_image_definitions[*].os_type must be 'Linux' or 'Windows'."
  }
  validation {
    condition     = alltrue([for v in var.compute_gallery_image_definitions : contains(["Generalized", "Specialized"], v.os_state)])
    error_message = "Each compute_gallery_image_definitions[*].os_state must be 'Generalized' or 'Specialized'."
  }
  validation {
    condition     = alltrue([for v in var.compute_gallery_image_definitions : contains(["V1", "V2"], v.hyper_v_generation)])
    error_message = "Each compute_gallery_image_definitions[*].hyper_v_generation must be 'V1' or 'V2'."
  }
  validation {
    condition     = alltrue([for v in var.compute_gallery_image_definitions : contains(["x64", "Arm64"], v.architecture)])
    error_message = "Each compute_gallery_image_definitions[*].architecture must be 'x64' or 'Arm64'."
  }
}

variable "image_template_image_source" {
  type = object({
    type             = string
    publisher        = optional(string, null)
    offer            = optional(string, null)
    sku              = optional(string, null)
    version          = optional(string, null)
    image_id         = optional(string, null)
    image_version_id = optional(string, null)
    plan_info = optional(object({
      plan_name      = string
      plan_product   = string
      plan_publisher = string
    }), null)
  })
  description = <<DESCRIPTION
The image source for the image template. Must include `type` and the appropriate fields for that type.

- `type` - (Required) The type of image source. Possible values: `PlatformImage`, `ManagedImage`, `SharedImageVersion`.
- `publisher` - (Required for PlatformImage) The image publisher.
- `offer` - (Required for PlatformImage) The image offer.
- `sku` - (Required for PlatformImage) The image SKU.
- `version` - (Required for PlatformImage) The image version. Use `latest` to resolve at build time.
- `image_id` - (Required for ManagedImage) The ARM resource ID of the managed image.
- `image_version_id` - (Required for SharedImageVersion) The ARM resource ID of the shared image version.
- `plan_info` - (Optional, PlatformImage only) Purchase plan info for Marketplace images.
DESCRIPTION
  nullable    = false

  validation {
    condition     = contains(["PlatformImage", "ManagedImage", "SharedImageVersion"], var.image_template_image_source.type)
    error_message = "image_template_image_source.type must be one of: 'PlatformImage', 'ManagedImage', 'SharedImageVersion'."
  }
  validation {
    condition = var.image_template_image_source.type != "PlatformImage" || (
      var.image_template_image_source.publisher != null &&
      var.image_template_image_source.offer != null &&
      var.image_template_image_source.sku != null &&
      var.image_template_image_source.version != null
    )
    error_message = "PlatformImage source requires publisher, offer, sku, and version."
  }
  validation {
    condition     = var.image_template_image_source.type != "ManagedImage" || var.image_template_image_source.image_id != null
    error_message = "ManagedImage source requires image_id."
  }
  validation {
    condition     = var.image_template_image_source.type != "SharedImageVersion" || var.image_template_image_source.image_version_id != null
    error_message = "SharedImageVersion source requires image_version_id."
  }
}

variable "location" {
  type        = string
  description = "Azure region where the resources should be deployed."
  nullable    = false
}

variable "name" {
  type        = string
  description = "The base name used for naming resources (e.g., image template, gallery)."
  nullable    = false
}

variable "parent_id" {
  type        = string
  description = "The resource ID of the resource group in which to create all resources."
  nullable    = false
}

variable "build" {
  type = object({
    enabled    = optional(bool, false)
    trigger_id = optional(string, "1")
  })
  default     = { enabled = false }
  description = <<DESCRIPTION
Controls whether to trigger an image build after creating the template.

- `enabled` - (Optional) Whether to trigger the build. Defaults to false.
- `trigger_id` - (Optional) Change this value to force a new build. Defaults to "1".
DESCRIPTION
  nullable    = false
}

variable "build_timeout_in_minutes" {
  type        = number
  default     = 240
  description = "The maximum time in minutes for the image build. 0 means use default (240 min). Max 960."
  nullable    = false

  validation {
    condition     = var.build_timeout_in_minutes >= 0 && var.build_timeout_in_minutes <= 960
    error_message = "build_timeout_in_minutes must be between 0 and 960."
  }
}

variable "compute_gallery_name" {
  type        = string
  default     = null
  description = "The name of the Azure Compute Gallery. If null, a name will be generated from `var.name`."
}

variable "diagnostic_settings" {
  type = map(object({
    name                                     = optional(string, null)
    log_categories                           = optional(set(string), [])
    log_groups                               = optional(set(string), ["allLogs"])
    metric_categories                        = optional(set(string), ["AllMetrics"])
    log_analytics_destination_type           = optional(string, "Dedicated")
    workspace_resource_id                    = optional(string, null)
    storage_account_resource_id              = optional(string, null)
    event_hub_authorization_rule_resource_id = optional(string, null)
    event_hub_name                           = optional(string, null)
    marketplace_partner_resource_id          = optional(string, null)
  }))
  default     = {}
  description = "A map of diagnostic settings to create on the resources."
  nullable    = false
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see <https://aka.ms/avm/telemetryinfo>.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
  nullable    = false
}

variable "image_template_customization_steps" {
  type        = any
  default     = null
  description = <<DESCRIPTION
A list of customization steps for the image template. Each step must have a `type` field.
Supported types: `Shell`, `PowerShell`, `WindowsRestart`, `WindowsUpdate`, `File`.
DESCRIPTION

  validation {
    condition     = var.image_template_customization_steps == null || alltrue([for step in var.image_template_customization_steps : lookup(step, "type", null) != null])
    error_message = "Each customization step must have a 'type' field."
  }
}

variable "image_template_distribute" {
  type = list(object({
    type             = string
    run_output_name  = string
    gallery_image_id = optional(string, null)
    target_regions = optional(list(object({
      name                 = string
      replica_count        = optional(number, 1)
      storage_account_type = optional(string, "Standard_ZRS")
    })), null)
    exclude_from_latest = optional(bool, false)
    artifact_tags       = optional(map(string), null)
    image_id            = optional(string, null)
    location            = optional(string, null)
    versioning = optional(object({
      scheme = string
      major  = optional(number, null)
    }), null)
  }))
  default     = null
  description = "Distribution targets for the image template. If null, a default SharedImage distribution to the compute gallery will be created."

  validation {
    condition     = var.image_template_distribute == null || alltrue([for d in coalesce(var.image_template_distribute, []) : contains(["SharedImage", "ManagedImage"], d.type)])
    error_message = "Each image_template_distribute[*].type must be 'SharedImage' or 'ManagedImage' (VHD distribution is not supported in this version)."
  }
  validation {
    condition     = var.image_template_distribute == null || alltrue([for d in coalesce(var.image_template_distribute, []) : d.type != "ManagedImage" || (d.image_id != null && d.location != null)])
    error_message = "ManagedImage distribute entries require both image_id and location."
  }
  validation {
    condition     = var.image_template_distribute == null || alltrue([for d in coalesce(var.image_template_distribute, []) : d.versioning == null || contains(["Latest", "Source"], d.versioning.scheme)])
    error_message = "image_template_distribute[*].versioning.scheme must be 'Latest' or 'Source'."
  }
}

variable "image_template_name" {
  type        = string
  default     = null
  description = "The name of the image template. If null, a name will be generated from `var.name`."
}

variable "lock" {
  type = object({
    kind = string
    name = optional(string, null)
  })
  default     = null
  description = <<DESCRIPTION
Controls the Resource Lock configuration for the image template resource.

- `kind` - (Required) The type of lock. Possible values are `"CanNotDelete"` and `"ReadOnly"`.
- `name` - (Optional) The name of the lock.
DESCRIPTION

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "The lock level must be one of: 'CanNotDelete', or 'ReadOnly'."
  }
}

variable "managed_identities" {
  type = object({
    system_assigned            = optional(bool, false)
    user_assigned_resource_ids = optional(set(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
Controls the Managed Identity configuration on the compute gallery resource via the AVM interfaces module.
Note: The image template always uses a module-created user-assigned identity for the AIB service.

- `system_assigned` - (Optional) Specifies if the System Assigned Managed Identity should be enabled on the gallery.
- `user_assigned_resource_ids` - (Optional) Specifies a list of User Assigned Managed Identity resource IDs to be assigned to the gallery.
DESCRIPTION
  nullable    = false
}

variable "optimize_vm_boot" {
  type        = bool
  default     = true
  description = "Enable VM boot optimization for the image template."
  nullable    = false
}

variable "rbac_propagation_delay_seconds" {
  type        = number
  default     = 300
  description = "Seconds to wait after RBAC assignments before creating the image template."
  nullable    = false
}

variable "role_assignments" {
  type = map(object({
    name                                   = optional(string, null)
    role_definition_id_or_name             = string
    principal_id                           = string
    description                            = optional(string, null)
    skip_service_principal_aad_check       = optional(bool, false)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
    principal_type                         = optional(string, null)
  }))
  default     = {}
  description = "A map of role assignments to create on the image template resource."
  nullable    = false
}

variable "staging_resource_group_name" {
  type        = string
  default     = null
  description = <<DESCRIPTION
The name of the resource group used by AIB for temporary build resources (staging VMs, storage accounts).
If set, the module creates this resource group and grants the image builder identity Contributor access.
This is required for builds to succeed when the subscription has restrictive storage policies.
If null, AIB creates a random staging resource group (which may fail under restrictive policies).
DESCRIPTION
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "(Optional) Tags of the resources."
}

variable "vm_profile" {
  type = object({
    vm_size         = optional(string, "Standard_D2s_v3")
    os_disk_size_gb = optional(number, null)
    vnet_config = optional(object({
      subnet_id                    = string
      container_instance_subnet_id = optional(string, null)
      proxy_vm_size                = optional(string, null)
    }), null)
  })
  default     = {}
  description = <<DESCRIPTION
The VM profile for the image build.

- `vm_size` - (Optional) The VM size for the build. Defaults to `Standard_D2s_v3`.
- `os_disk_size_gb` - (Optional) The OS disk size in GB.
- `vnet_config` - (Optional) VNet integration for private builds.
DESCRIPTION
  nullable    = false
}
