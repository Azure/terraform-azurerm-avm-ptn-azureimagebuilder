# Deploy all (Linux)

Full-stack image build for Linux, mirroring the Bicep
`avm/ptn/virtual-machine-images/azure-image-builder` `deployAll.linux` test.

This example is self-contained: the caller provisions every resource the
build needs and the module focuses on the AIB primitives.

What this example deploys:

- Resource group
- Virtual network with two subnets (build subnet, ACI-delegated subnet)
- The image builder pattern module (gallery + identity + image template)
- A build trigger that fires after the image template is ready

The customization uses an inline shell step to write a marker file during the
image build.
