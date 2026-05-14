locals {
  compute_gallery_name             = coalesce(var.compute_gallery_name, "gal_${replace(var.name, "-", "_")}")
  contributor_role_definition_guid = "b24988ac-6180-42a0-ab88-20f7382dd24c"
  contributor_role_definition_id   = provider::azapi::subscription_resource_id(data.azapi_client_config.current.subscription_id, "Microsoft.Authorization/roleDefinitions", [local.contributor_role_definition_guid])
  default_gallery_image_id         = "${azapi_resource.compute_gallery.id}/images/${local.resolved_image_definition_name}"
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
      versioning = {
        scheme = "Latest"
        major  = 1
      }
    }
  ])
  gallery_image_version_cleanup_targets = var.build.enabled && var.build.cleanup_gallery_image_version_on_destroy ? {
    for distribution_index, distribution in local.distribute_input : distribution_index => {
      gallery_image_id = coalesce(distribution.gallery_image_id, local.default_gallery_image_id)
    }
    if distribution.type == "SharedImage"
  } : {}
  image_builder_identity_id           = var.image_builder_identity_resource_id != null ? var.image_builder_identity_resource_id : azapi_resource.image_builder_identity[0].id
  image_builder_identity_principal_id = var.image_builder_identity_resource_id != null ? data.azapi_resource.image_builder_identity[0].output.properties.principalId : azapi_resource.image_builder_identity[0].output.properties.principalId
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
  image_template_name                      = coalesce(var.image_template_name, "it-${var.name}")
  network_contributor_role_definition_guid = "4d97b98b-1d4f-4787-a291-c67834d212e7"
  network_contributor_role_definition_id   = provider::azapi::subscription_resource_id(data.azapi_client_config.current.subscription_id, "Microsoft.Authorization/roleDefinitions", [local.network_contributor_role_definition_guid])
  # Resolve image-definition name from either the map key or the explicit `.name`.
  # The Azure Compute Gallery image path uses the resource name, not the Terraform map key.
  resolved_image_definition_name = lookup(var.compute_gallery_image_definitions, var.compute_gallery_image_definition_name, null) != null ? var.compute_gallery_image_definitions[var.compute_gallery_image_definition_name].name : one([for k, v in var.compute_gallery_image_definitions : v.name if v.name == var.compute_gallery_image_definition_name])
  staging_resource_group_id      = var.staging_resource_group_resource_id != null ? var.staging_resource_group_resource_id : try(azapi_resource.staging_resource_group[0].id, null)
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
  vnet_id = local.vnet_subnet_resource != null ? provider::azapi::resource_group_resource_id(local.vnet_subnet_resource.subscription_id, local.vnet_subnet_resource.resource_group_name, "Microsoft.Network/virtualNetworks", [local.vnet_subnet_resource.parts.virtualNetworks]) : null
  # VNet subnet → parent VNet ID (subnet RBAC scope can be the subnet itself, but
  # Network Contributor must propagate from the VNet for AIB to attach NICs).
  vnet_subnet_id       = try(var.vm_profile.vnet_config.subnet_id, null)
  vnet_subnet_resource = local.vnet_subnet_id != null ? provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks/subnets", local.vnet_subnet_id) : null
}
