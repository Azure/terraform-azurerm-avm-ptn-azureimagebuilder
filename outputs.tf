output "compute_gallery_id" {
  description = "The resource ID of the Azure Compute Gallery."
  value       = azapi_resource.compute_gallery.id
}

output "image_builder_identity_id" {
  description = "The resource ID of the image builder user-assigned identity."
  value       = local.image_builder_identity_id
}

output "image_builder_identity_principal_id" {
  description = "The principal ID of the image builder user-assigned identity."
  value       = local.image_builder_identity_principal_id
}

output "image_template_id" {
  description = "The resource ID of the image template."
  value       = azapi_resource.image_template.id
}

output "image_template_name" {
  description = "The name of the image template."
  value       = azapi_resource.image_template.name
}

output "name" {
  description = "The name of the primary resource (image template)."
  value       = azapi_resource.image_template.name
}

output "resource" {
  description = "The full image template resource object."
  value       = azapi_resource.image_template
}

output "resource_id" {
  description = "The resource ID of the image template (primary resource)."
  value       = azapi_resource.image_template.id
}
