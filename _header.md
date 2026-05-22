# terraform-azurerm-avm-ptn-azureimagebuilder

This module deploys an Azure Image Builder pipeline using the AzAPI provider.

It orchestrates the creation of a User-Assigned Managed Identity, Azure Compute Gallery with image definitions, RBAC assignments, and an AIB Image Template. Optionally triggers the image build process.

## Features

- Azure Compute Gallery with customizable image definitions
- Image Template with support for PlatformImage, ManagedImage, and SharedImageVersion sources
- Customization steps (Shell, PowerShell, WindowsRestart, WindowsUpdate, File)
- Flexible distribution targets with region replication
- VNet integration for private builds
- Opt-in VM boot optimization for supported regions
- Opt-in build triggering with nonce-based re-trigger support and Shared Image Gallery version cleanup on destroy
- Managed identity with BYO support and automatic RBAC wiring
- Optional module-created or BYO staging resource group for build resources
- Resource locks and role assignments via AVM interfaces module
- AVM telemetry

## Naming notes

Azure Compute Gallery names can contain alphanumerics, underscores, and periods, but they cannot contain hyphens. When `compute_gallery_name` is null, the generated gallery name replaces hyphens in `name` with underscores. Set `compute_gallery_name` to use a specific compliant gallery name.
