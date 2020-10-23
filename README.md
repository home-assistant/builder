# Home Assistant builder

_Multi-purpose cross-compile docker builder._

## GitHub Action

You can use this repository as a GitHub action to test and/or publish your builds.

Use the `with.args` key to pass in arguments to the builder, to see what arguments are supported you can look at the [arguments](#Arguments) section.

To spesify a version of the runner you want to use, set the `with.version` key, this defaults to `dev`.

### Test action example

```yaml
name: 'Test'

on: [push, pull_request]

jobs:
  build:
    name: Test build
    runs-on: ubuntu-latest
    steps:
    - name: Checkout the repository
      uses: actions/checkout@v2
    - name: Test build
      uses: home-assistant/builder@master
      with:
        args: |
          --test \
          --all \
          --target /data \
          --docker-hub userspace-name
```

### Publish action example

```yaml
name: 'Publish'

on:
  release:
    types: [published]

jobs:
  publish:
    name: Publish
    runs-on: ubuntu-latest
    steps:
    - name: Checkout the repository
      uses: actions/checkout@v2
    - name: Login to DockerHub
      uses: docker/login-action@v1
      with:
        username: ${{ secrets.DOCKERHUB_USERNAME }}
        password: ${{ secrets.DOCKERHUB_TOKEN }}
    - name: Publish
      uses: home-assistant/builder@master
      with:
        args: |
          --all \
          --target /data \
          --docker-hub userspace-name
```

## Arguments

```
Options:
-h, --help
      Display this help and exit.

Repository / Data
  -r, --repository <REPOSITORY>
      Set git repository to load data from.
  -b, --branch <BRANCH>
      Set git branch for repository.
  -t, --target <PATH_TO_BUILD>
      Set local folder or path inside repository for build.

Version/Image handling
  -v, --version <VERSION>
      Overwrite version/tag of build.
  -i, --image <IMAGE_NAME>
      Overwrite image name of build / support {arch}.
  --release <VERSION>
      Additional version information like for base images.
  --release-tag
      Use this as main tag.

Architecture
  --armhf
      Build for arm v6.
  --armv7
      Build for arm v7.
  --amd64
      Build for intel/amd 64bit.
  --aarch64
      Build for arm 64bit.
  --i386
      Build for intel/amd 32bit.
  --all
      Build all architecture.

Build handling
  --test
      Disable push to dockerhub.
  --no-latest
      Do not tag images as latest.
  --no-cache
      Disable cache for the build (from latest).
  --self-cache
      Use same tag as cache tag instead latest.
  --cache-tag
      Use a custom tag for the build cache.
  -d, --docker-hub <DOCKER_REPOSITORY>
      Set or overwrite the docker repository.
  --docker-hub-check
      Check if the version already exists before starting the build.
  --docker-user
      Username to login into docker with
  --docker-password
      Password to login into docker with
  --no-crossbuild-cleanup
      Don't cleanup the crosscompile feature (for multiple builds)

  Use the host docker socket if mapped into container:
      /var/run/docker.sock

Internals:
  --addon
      Default on. Run all things for an addon build.
  --generic <VERSION>
      Build based on the build.json
  --builder-wheels <PYTHON_TAG>
      Build the wheels builder for Home Assistant.
  --base <VERSION>
      Build our base images.
  --base-python <VERSION=ALPINE>
      Build our base python images.
  --base-raspbian <VERSION>
      Build our base raspbian images.
  --base-ubuntu <VERSION>
      Build our base ubuntu images.
  --base-debian <VERSION>
      Build our base debian images.
  --homeassisant-landingpage
      Build the landingpage for machines.
  --homeassistant-machine <VERSION=ALL,X,Y>
      Build the machine based image for a release.
```

## Local installation

amd64:
```bash
docker pull homeassistant/amd64-builder
```

armv7/armhf:
```bash
docker pull homeassistant/armv7-builder
```

aarch64:
```bash
docker pull homeassistant/aarch64-builder
```

## Run

**For remote git repository:**

```bash
docker run \
	--rm \
	--privileged \
	-v ~/.docker:/root/.docker \
	homeassistant/amd64-builder \
		--all \
		-t addon-folder \
		-r https://github.com/xy/addons \
		-b branchname
```

**For local git repository:**

```bash
docker run \
	--rm \
	--privileged \
	-v ~/.docker:/root/.docker \
	-v /my_addon:/data \
	homeassistant/amd64-builder \
		--all \
		-t /data
```

## Docker Daemon

By default, the image will run docker-in-docker. You can use the host docker daemon by bind mounting the host docker socket to `/var/run/docker.sock` inside the container. For example, to do this with the _Local repository_ example above (assuming the host docker socket is at `/var/run/docker.sock`:

```bash
docker run \
	--rm \
	--privileged \
	-v ~/.docker:/root/.docker \
	-v /var/run/docker.sock:/var/run/docker.sock:ro \
	-v /my_addon:/data \
	homeassistant/amd64-builder \
		--all \
		-t /data
```

## Help

```bash
docker run --rm --privileged homeassistant/amd64-builder --help
```
