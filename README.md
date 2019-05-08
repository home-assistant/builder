[![Build Status](https://dev.azure.com/home-assistant/Hass.io/_apis/build/status/builder?branchName=master)](https://dev.azure.com/home-assistant/Hass.io/_build/latest?definitionId=4&branchName=master)

# Build docker env

## Install

amd64:
```bash
$ docker pull homeassistant/amd64-builder
```

armv7/armhf:
```bash
$ docker pull homeassistant/armv7-builder
```

aarch64:
```bash
$ docker pull homeassistant/aarch64-builder
```

## Run

GIT repository:
```bash
$ docker run --rm --privileged -v ~/.docker:/root/.docker homeassistant/amd64-builder --all -t addon-folder -r https://github.com/xy/addons -b branchname
```

Local repository:
```bash
docker run --rm --privileged -v ~/.docker:/root/.docker -v /my_addon:/data homeassistant/amd64-builder --all -t /data
```

## Help

```bash
$ docker run --rm --privileged homeassistant/amd64-builder --help
```
