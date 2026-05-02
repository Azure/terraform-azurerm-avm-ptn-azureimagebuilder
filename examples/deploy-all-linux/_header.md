# Deploy all (Linux)

Full-stack image build for Linux, mirroring the Bicep
`avm/ptn/virtual-machine-images/azure-image-builder` `deployAll.linux` test.

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

The customizations download `Install-LinuxPowerShell.sh` from blob storage,
stage `Initialize-LinuxSoftware.ps1` onto the build VM, and run it.
