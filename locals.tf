locals {
  compute_gallery_name = coalesce(var.compute_gallery_name, "gal_${replace(var.name, "-", "_")}")
  # Build distribute targets - default to SharedImage if not provided
  default_gallery_image_id = "${azapi_resource.compute_gallery.id}/images/${var.compute_gallery_image_definition_name}"
  distribute = var.image_template_distribute != null ? [
    for d in var.image_template_distribute : {
      type              = d.type
      runOutputName     = d.run_output_name
      galleryImageId    = d.gallery_image_id
      excludeFromLatest = d.exclude_from_latest
      artifactTags      = d.artifact_tags
      imageId           = d.image_id
      location          = d.location
      targetRegions = d.target_regions != null ? [
        for tr in d.target_regions : {
          name               = tr.name
          replicaCount       = tr.replica_count
          storageAccountType = tr.storage_account_type
        }
      ] : null
      versioning = d.versioning != null ? {
        scheme = d.versioning.scheme
        major  = d.versioning.major
      } : null
    }
    ] : [
    {
      type           = "SharedImage"
      runOutputName  = "${var.name}-output"
      galleryImageId = local.default_gallery_image_id
      targetRegions = [{
        name               = var.location
        replicaCount       = 1
        storageAccountType = "Standard_LRS"
      }]
    }
  ]
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
  image_source_platform = {
    type      = "PlatformImage"
    publisher = var.image_template_image_source.publisher
    offer     = var.image_template_image_source.offer
    sku       = var.image_template_image_source.sku
    version   = var.image_template_image_source.version
  }
  image_source_shared = {
    type           = "SharedImageVersion"
    imageVersionId = var.image_template_image_source.image_version_id
  }
  image_template_name = coalesce(var.image_template_name, "it-${var.name}")
  # VM profile
  vm_profile = {
    vmSize                 = var.vm_profile.vm_size
    osDiskSizeGB           = coalesce(var.vm_profile.os_disk_size_gb, 0)
    userAssignedIdentities = [azapi_resource.image_builder_identity.id]
    vnetConfig = var.vm_profile.vnet_config != null ? {
      subnetId                  = var.vm_profile.vnet_config.subnet_id
      containerInstanceSubnetId = var.vm_profile.vnet_config.container_instance_subnet_id
      proxyVmSize               = var.vm_profile.vnet_config.proxy_vm_size
    } : null
  }
}
