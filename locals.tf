locals {
  compute_gallery_name     = coalesce(var.compute_gallery_name, "gal_${replace(var.name, "-", "_")}")
  default_gallery_image_id = "${azapi_resource.compute_gallery.id}/images/${local.resolved_image_definition_name}"
  # Per-type distribute body: only SharedImage uses galleryImageId/targetRegions/versioning;
  # ManagedImage uses imageId+location; VHD would use uri (not supported in v0.1).
  distribute = [
    for d in local.distribute_input : {
      for k, v in {
        type              = d.type
        runOutputName     = d.run_output_name
        excludeFromLatest = d.exclude_from_latest
        artifactTags      = d.artifact_tags
        galleryImageId    = d.type == "SharedImage" ? coalesce(d.gallery_image_id, local.default_gallery_image_id) : null
        targetRegions = d.type == "SharedImage" && d.target_regions != null ? [
          for tr in d.target_regions : {
            name               = tr.name
            replicaCount       = tr.replica_count
            storageAccountType = tr.storage_account_type
          }
        ] : null
        versioning = d.type == "SharedImage" && d.versioning != null ? {
          for vk, vv in {
            scheme = d.versioning.scheme
            major  = d.versioning.major
          } : vk => vv if vv != null
        } : null
        imageId  = d.type == "ManagedImage" ? d.image_id : null
        location = d.type == "ManagedImage" ? d.location : null
      } : k => v if v != null
    }
  ]
  distribute_input = coalesce(var.image_template_distribute, [
    {
      type             = "SharedImage"
      run_output_name  = "${var.name}-output"
      gallery_image_id = null
      target_regions = [{
        name                 = var.location
        replica_count        = 1
        storage_account_type = "Standard_ZRS"
      }]
      exclude_from_latest = false
      artifact_tags       = null
      image_id            = null
      location            = null
      versioning          = null
    }
  ])
  image_source = (
    var.image_template_image_source.type == "PlatformImage" ? local.image_source_platform :
    var.image_template_image_source.type == "ManagedImage" ? local.image_source_managed :
    local.image_source_shared
  )
  image_source_managed = {
    type    = "ManagedImage"
    imageId = var.image_template_image_source.image_id
  }
  # Build the image source object for the ARM body based on type
  image_source_platform = merge(
    {
      type      = "PlatformImage"
      publisher = var.image_template_image_source.publisher
      offer     = var.image_template_image_source.offer
      sku       = var.image_template_image_source.sku
      version   = var.image_template_image_source.version
    },
    var.image_template_image_source.plan_info != null ? {
      planInfo = {
        planName      = var.image_template_image_source.plan_info.plan_name
        planProduct   = var.image_template_image_source.plan_info.plan_product
        planPublisher = var.image_template_image_source.plan_info.plan_publisher
      }
    } : {}
  )
  image_source_shared = {
    type           = "SharedImageVersion"
    imageVersionId = var.image_template_image_source.image_version_id
  }
  image_template_name = coalesce(var.image_template_name, "it-${var.name}")
  # Resolve image-definition name from either the map key or the explicit `.name`.
  # The Azure Compute Gallery image path uses the resource name, not the Terraform map key.
  resolved_image_definition_name = lookup(var.compute_gallery_image_definitions, var.compute_gallery_image_definition_name, null) != null ? var.compute_gallery_image_definitions[var.compute_gallery_image_definition_name].name : one([for k, v in var.compute_gallery_image_definitions : v.name if v.name == var.compute_gallery_image_definition_name])
  # VM profile — filter null values to avoid sending zero defaults
  vm_profile = {
    for k, v in {
      vmSize       = var.vm_profile.vm_size
      osDiskSizeGB = var.vm_profile.os_disk_size_gb
      vnetConfig = var.vm_profile.vnet_config != null ? {
        for vk, vv in {
          subnetId                  = var.vm_profile.vnet_config.subnet_id
          containerInstanceSubnetId = var.vm_profile.vnet_config.container_instance_subnet_id
          proxyVmSize               = var.vm_profile.vnet_config.proxy_vm_size
        } : vk => vv if vv != null
      } : null
    } : k => v if v != null
  }
  vnet_id = local.vnet_subnet_id != null ? regex("^(/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+)", local.vnet_subnet_id)[0] : null
  # VNet subnet → parent VNet ID (subnet RBAC scope can be the subnet itself, but
  # Network Contributor must propagate from the VNet for AIB to attach NICs).
  vnet_subnet_id = try(var.vm_profile.vnet_config.subnet_id, null)
}
