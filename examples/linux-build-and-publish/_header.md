# Linux Build and Publish Example

This example creates the full Azure Image Builder pipeline and triggers an image build. The build will bake an Ubuntu 24.04 image with custom packages and publish it to the compute gallery.

> **Note:** Image builds take 15-60+ minutes. Change `build.trigger_id` to force a new build.
