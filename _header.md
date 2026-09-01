# terraform-azurerm-avm-ptn-azureimagebuilder

This module deploys an Azure Image Builder pipeline using the AzAPI provider.

It orchestrates the creation of a User-Assigned Managed Identity, Azure Compute Gallery with image definitions, RBAC assignments, and an AIB Image Template. Optionally triggers the image build process.

## Features

- Azure Compute Gallery with customizable image definitions
- Image Template with support for PlatformImage, ManagedImage, and SharedImageVersion sources
- Customization steps (Shell, PowerShell, WindowsRestart, WindowsUpdate, File)
- Shared Image, managed image, and VHD distribution targets
- VNet integration for private builds
- Opt-in VM boot optimization for supported regions
- Opt-in build triggering with nonce-based re-trigger support and Shared Image Gallery version cleanup on destroy
- Managed identity with BYO support and automatic RBAC wiring
- Optional module-created or BYO staging resource group for build resources
- Resource locks and role assignments via AVM interfaces module
- AVM telemetry

## Naming notes

Azure Compute Gallery names can contain alphanumerics, underscores, and periods, but they cannot contain hyphens. When `compute_gallery_name` is null, the generated gallery name replaces hyphens in `name` with underscores. Set `compute_gallery_name` to use a specific compliant gallery name.

## Secure VHD distribution

Set `image_template_distribute[*].type` to `VHD` to produce a VHD artifact. Set `uri` to a full HTTPS blob URI for a custom destination, or omit it to use the Image Builder staging resource group.

For a custom destination, grant the Image Builder user-assigned managed identity the minimum required data-plane access, such as `Storage Blob Data Contributor` scoped to the destination storage account or container. Keep anonymous blob access disabled. Avoid SAS tokens and other credentials in `uri`, because Terraform records this value in plans and state.
