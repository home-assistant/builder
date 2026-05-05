# Home Assistant Builder

_Tooling used for building of Home Assistant container images._

## Reusable GitHub Actions

This repository provides a set of the following composable GitHub Actions for building, signing, and publishing multi-arch container images. They are designed to be used together in a workflow but some of them can be used standalone as well.

### [`prepare-multi-arch-matrix`](actions/prepare-multi-arch-matrix/action.yml)

Takes a JSON array of architectures (e.g., `["amd64", "aarch64"]`) and an image name, and outputs a GitHub Actions build matrix suited for use with `build-image`.

### [`build-image`](actions/build-image/action.yml)

Builds a single-arch container image using Docker Buildx with optional push and Cosign signing. Supports GHA and registry-based build caching, base image signature verification, and custom build args/labels. Outputs the image digest.

### [`publish-multi-arch-manifest`](actions/publish-multi-arch-manifest/action.yml)

Combines per-architecture images (e.g., `amd64-myimage:latest`, `aarch64-myimage:latest`) into a single multi-arch manifest (e.g., `myimage:latest`) using `docker buildx imagetools create`. Optionally signs the resulting manifest with Cosign.

### [`cosign-verify`](actions/cosign-verify/action.yml)

Verifies Cosign signatures on container images with up to 5 retries and exponential backoff. Supports an allow-failure mode that emits a warning instead of failing. Used internally by `build-image` for cache and base image verification, but can also be used standalone.

## Example workflow

The following example workflow builds multi-arch container images when a GitHub release is published. It prepares a build matrix, builds per-architecture images in parallel (e.g., `ghcr.io/owner/amd64-my-image`, `ghcr.io/owner/aarch64-my-image`), and then combines them into a single multi-arch manifest (`ghcr.io/owner/my-image`).

> 📝 Replace `[version]` with the desired tag from the [releases](https://github.com/home-assistant/builder/releases) page.

> 📝 This workflow works also for `push` triggers in case you want to build and publish an image on every git push 
> but you may want to change the `image-tags` because on `push` triggers the `${{ github.event.release.tag_name }}`
> will expand to an empty string.


```yaml
name: Build

on:
  release:
    types: [published]

env:
  ARCHITECTURES: '["amd64", "aarch64"]'
  IMAGE_NAME: my-image

permissions:
  contents: read

jobs:
  init:
    name: Initialize build
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.matrix.outputs.matrix }}
    steps:
      - uses: actions/checkout@v6

      - name: Get build matrix
        id: matrix
        uses: home-assistant/builder/actions/prepare-multi-arch-matrix@[version]
        with:
          architectures: ${{ env.ARCHITECTURES }}
          image-name: ${{ env.IMAGE_NAME }}

  build:
    name: Build ${{ matrix.arch }} image
    needs: init
    runs-on: ${{ matrix.os }}
    permissions:
      contents: read # To check out the code
      id-token: write # Write needed for Cosign signing (issue OIDC token for signing)
      packages: write # To push built images to GitHub Container Registry
    strategy:
      fail-fast: false
      matrix: ${{ fromJSON(needs.init.outputs.matrix) }}
    steps:
      - uses: actions/checkout@v6

      - name: Build image
        uses: home-assistant/builder/actions/build-image@[version]
        with:
          arch: ${{ matrix.arch }}
          container-registry-password: ${{ secrets.GITHUB_TOKEN }}
          image: ${{ matrix.image }}
          image-tags: |
            ${{ github.event.release.tag_name }}
            latest
          push: "true"
          version: ${{ github.event.release.tag_name }}

  manifest:
    name: Publish multi-arch manifest
    needs: [init, build]
    runs-on: ubuntu-latest
    permissions:
      id-token: write # Write needed for Cosign signing (issue OIDC token for signing)
      packages: write # To push the manifest to GitHub Container Registry
    steps:
      - name: Publish multi-arch manifest
        uses: home-assistant/builder/actions/publish-multi-arch-manifest@[version]
        with:
          architectures: ${{ env.ARCHITECTURES }}
          container-registry-password: ${{ secrets.GITHUB_TOKEN }}
          image-name: ${{ env.IMAGE_NAME }}
          image-tags: |
            ${{ github.event.release.tag_name }}
            latest
```

## Legacy `home-assistant/builder` action

The `home-assistant/builder` action is deprecated and no longer maintained, the last official release was [2026.02.1](https://github.com/home-assistant/builder/blob/2026.02.1/README.md). If you came here because you see the warning in your action, migrate to the new actions above. We will remove the `home-assistant/builder` action soon, which will break your GitHub action if it is still using `home-assistant/builder@master` at that time.

### Migration Guide

Please refer to the [Migrating app builds to Docker BuildKit](https://developers.home-assistant.io/blog/2026/04/02/builder-migration/) blog post for the migration process.
