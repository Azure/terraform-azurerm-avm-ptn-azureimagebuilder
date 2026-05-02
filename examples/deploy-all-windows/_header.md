# Deploy all (Windows)

Full-stack image build for Windows, mirroring the Bicep
`avm/ptn/virtual-machine-images/azure-image-builder` `deployAll.windows` test.

This example is self-contained — the caller provisions every resource the
build needs and the module focuses on the AIB primitives.

What this example deploys:

- Resource group
- Virtual network with two subnets (build subnet, ACI-delegated subnet)
- Storage account, blob container, and two uploaded scripts
- The image builder pattern module (gallery + identity + image template)
- A role assignment granting the image builder identity
  `Storage Blob Data Reader` on the container, plus an RBAC propagation wait
- A build trigger that fires after RBAC has settled

The customizations download `Install-WindowsPowerShell.ps1` from blob
storage, stage `Initialize-WindowsSoftware.ps1` onto the build VM, run it,
restart, then apply Windows Updates.
