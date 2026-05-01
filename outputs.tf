output "compute_gallery_id" {
  description = "The resource ID of the Azure Compute Gallery."
  value       = azapi_resource.compute_gallery.id
}

output "image_builder_identity_id" {
  description = "The resource ID of the image builder user-assigned identity."
  value       = azapi_resource.image_builder_identity.id
}

output "image_builder_identity_principal_id" {
  description = "The principal ID of the image builder user-assigned identity."
  value       = azapi_resource.image_builder_identity.output.properties.principalId
}

output "image_template_id" {
  description = "The resource ID of the image template."
  value       = azapi_resource.image_template.id
}

output "image_template_name" {
  description = "The name of the image template."
  value       = azapi_resource.image_template.name
}

output "resource_id" {
  description = "The resource ID of the image template (primary resource)."
  value       = azapi_resource.image_template.id
}
