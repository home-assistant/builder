#!/usr/bin/env bashio
######################
# Hass.io Build-env
######################
set -e
set +u

#### Variable ####

DOCKER_TIMEOUT=20
DOCKER_PID=-1
DOCKER_HUB=
DOCKER_HUB_CHECK=false
DOCKER_CACHE=true
DOCKER_LATEST=true
DOCKER_PUSH=true
DOCKER_USER=
DOCKER_PASSWORD=
DOCKER_LOCAL=false
CROSSBUILD_CLEANUP=true
SELF_CACHE=false
CUSTOM_CACHE_TAG=
RELEASE_TAG=false
GIT_REPOSITORY=
GIT_BRANCH="master"
TARGET=
VERSION=
IMAGE=
RELEASE=
PYTHON=
ALPINE=
BUILD_LIST=()
BUILD_TYPE="addon"
BUILD_TASKS=()
BUILD_ERROR=()
declare -A BUILD_MACHINE=(
                          [intel-nuc]="amd64" \
                          [odroid-c2]="aarch64" \
                          [odroid-c4]="aarch64" \
                          [odroid-n2]="aarch64" \
                          [odroid-xu]="armv7" \
                          [qemuarm]="armhf" \
                          [qemuarm-64]="aarch64" \
                          [qemux86]="i386" \
                          [qemux86-64]="amd64" \
                          [raspberrypi]="armhf" \
                          [raspberrypi2]="armv7" \
                          [raspberrypi3]="armv7" \
                          [raspberrypi3-64]="aarch64" \
                          [raspberrypi4]="armv7" \
                          [raspberrypi4-64]="aarch64" \
                          [tinker]="armv7" )


#### Misc functions ####

function print_help() {
    cat << EOF
Hass.io build-env for ecosystem:
docker run --rm homeassistant/{arch}-builder:latest [options]

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
    --cache-tag <TAG>
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
EOF

    bashio::exit.nok
}

#### Docker functions ####

function start_docker() {
    local starttime
    local endtime

    if [ -S "/var/run/docker.sock" ]; then
        bashio::log.info "Using host docker setup with '/var/run/docker.sock'"
        DOCKER_LOCAL="true"
        return 0
    fi

    bashio::log.info "Starting docker."
    dockerd 2> /dev/null &
    DOCKER_PID=$!

    bashio::log.info "Waiting for docker to initialize..."
    starttime="$(date +%s)"
    endtime="$(date +%s)"
    until docker info >/dev/null 2>&1; do
        if [ $((endtime - starttime)) -le $DOCKER_TIMEOUT ]; then
            sleep 1
            endtime=$(date +%s)
        else
            bashio::exit.nok "Timeout while waiting for docker to come up"
        fi
    done
    bashio::log.info "Docker was initialized"
}


function stop_docker() {
    local starttime
    local endtime

    if [ "$DOCKER_LOCAL" == "true" ]; then
        return 0
    fi

    bashio::log.info "Stopping in container docker..."
    if [ "$DOCKER_PID" -gt 0 ] && kill -0 "$DOCKER_PID" 2> /dev/null; then
        starttime="$(date +%s)"
        endtime="$(date +%s)"

        # Now wait for it to die
        kill "$DOCKER_PID"
        while kill -0 "$DOCKER_PID" 2> /dev/null; do
            if [ $((endtime - starttime)) -le $DOCKER_TIMEOUT ]; then
                sleep 1
                endtime=$(date +%s)
            else
                bashio::exit.nok "Timeout while waiting for container docker to die"
            fi
        done
    else
        bashio::log.warning "Your host might have been left with unreleased resources"
    fi
}


function run_build() {
    local build_dir=$1
    local repository=$2
    local image=$3
    local version=$4
    local build_from=$5
    local build_arch=$6
    local docker_cli=("${!7}")
    local docker_tags=("${!8}")

    local push_images=()
    local cache_tag="latest"
    local metadata

    # Overwrites
    if [ -n "$DOCKER_HUB" ]; then repository="$DOCKER_HUB"; fi
    if [ -n "$IMAGE" ]; then image="$IMAGE"; fi

    # Replace {arch} with build arch for image
    # shellcheck disable=SC1117
    image="$(echo "$image" | sed -r "s/\{arch\}/$build_arch/g")"

    # Check if image exists on docker hub
    if [ "$DOCKER_HUB_CHECK" == "true" ]; then
        metadata="$(curl -s "https://hub.docker.com/v2/repositories/$repository/$image/tags/$version/")"

        if [ -n "$metadata" ] && [ "$(echo "$metadata" | jq --raw-output '.name')" == "$version" ]; then
            bashio::log.info "Skip build, found $image:$version on dockerhub"
            return 0
        else
            bashio::log.info "Start build, $image:$version is not on dockerhub"
        fi
    fi

    # Init Cache
    if [ "$DOCKER_CACHE" == "true" ]; then
        if [ -n "$CUSTOM_CACHE_TAG" ]; then
            cache_tag="$CUSTOM_CACHE_TAG"
        elif [ "$SELF_CACHE" == "true" ]; then
            cache_tag="$version"
        fi

        bashio::log.info "Init cache for $repository/$image:$version with tag $cache_tag"
        if docker pull "$repository/$image:$cache_tag" > /dev/null 2>&1; then
            docker_cli+=("--cache-from" "$repository/$image:$cache_tag")
        else
            docker_cli+=("--no-cache")
            bashio::log.warning "No cache image found. Disabling cache for this build."
        fi
    else
        docker_cli+=("--no-cache")
    fi

    # do we know the arch of build?
    if [ -n "$build_arch" ]; then
        docker_cli+=("--label" "io.hass.arch=$build_arch")
        docker_cli+=("--build-arg" "BUILD_ARCH=$build_arch")
    fi

    # Build image
    bashio::log.info "Run build for $repository/$image:$version"
    docker build --pull -t "$repository/$image:$version" \
        --label "io.hass.version=$version" \
        --build-arg "BUILD_FROM=$build_from" \
        --build-arg "BUILD_VERSION=$version" \
        "${docker_cli[@]}" \
        "$build_dir"

    # Success?
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        BUILD_ERROR+=("$repository/$image:$version")
        return 0
    fi

    push_images+=("$repository/$image:$version")
    bashio::log.info "Finish build for $repository/$image:$version"

    # Tag latest
    if [ "$DOCKER_LATEST" == "true" ]; then
        docker_tags+=("latest")
    fi

    # Tag images
    for tag_image in "${docker_tags[@]}"; do
        bashio::log.info "Create image tag: ${tag_image}"
        docker tag "$repository/$image:$version" "$repository/$image:$tag_image"
        push_images+=("$repository/$image:$tag_image")
    done

    # Push images
    if [ "$DOCKER_PUSH" == "true" ]; then
        for i in "${push_images[@]}"; do
            for j in {1..3}; do
                bashio::log.info "Start upload of $i (attempt #${j}/3)"
                if docker push "$i" > /dev/null 2>&1; then
                    bashio::log.info "Upload succeeded on attempt #${j}"
                    break
                fi
                if [[ "${j}" == "3" ]]; then
                    bashio::exit.nok "Upload failed on attempt #${j}"
                else
                    bashio::log.warning "Upload failed on attempt #${j}"
                    sleep 30
                fi
            done
        done
    fi
}


#### HassIO functions ####

function build_base_image() {
    local build_arch=$1

    local build_from=""
    local image="{arch}-base"
    local docker_cli=()
    local docker_tags=()

    # Set type
    docker_cli+=("--label" "io.hass.type=base")
    docker_cli+=("--label" "io.hass.base.version=$RELEASE")
    docker_cli+=("--label" "io.hass.base.name=alpine")
    docker_cli+=("--label" "io.hass.base.image=$DOCKER_HUB/$image")

    # Start build
    run_build "$TARGET/$build_arch" "$DOCKER_HUB" "$image" "$VERSION" \
        "$build_from" "$build_arch" docker_cli[@] docker_tags[@]
}

function build_base_python_image() {
    local build_arch=$1

    local image="{arch}-base-python"
    local build_from="homeassistant/${build_arch}-base:${ALPINE}"
    local version="${VERSION}-alpine${ALPINE}"
    local docker_cli=()
    local docker_tags=()

    # If latest python version/build
    if [ "$RELEASE_TAG" == "true" ]; then
        docker_tags=("$VERSION")
    fi

    # Set type
    docker_cli+=("--label" "io.hass.type=base")
    docker_cli+=("--label" "io.hass.base.version=$RELEASE")
    docker_cli+=("--label" "io.hass.base.name=python")
    docker_cli+=("--label" "io.hass.base.image=$DOCKER_HUB/$image")

    # Start build
    run_build "$TARGET/$VERSION" "$DOCKER_HUB" "$image" "$version" \
        "$build_from" "$build_arch" docker_cli[@] docker_tags[@]
}


function build_base_ubuntu_image() {
    local build_arch=$1

    local build_from=""
    local image="{arch}-base-ubuntu"
    local docker_cli=()
    local docker_tags=()

    # Select builder image
    if [ "$build_arch" == "armhf" ]; then
        bashio::log.error "$build_arch not supported for ubuntu"
        return 1
    fi

    # Set type
    docker_cli+=("--label" "io.hass.type=base")
    docker_cli+=("--label" "io.hass.base.version=$RELEASE")
    docker_cli+=("--label" "io.hass.base.name=ubuntu")
    docker_cli+=("--label" "io.hass.base.image=$DOCKER_HUB/$image")

    # Start build
    run_build "$TARGET/$build_arch" "$DOCKER_HUB" "$image" "$VERSION" \
        "$build_from" "$build_arch" docker_cli[@] docker_tags[@]
}


function build_base_debian_image() {
    local build_arch=$1

    local build_from=""
    local image="{arch}-base-debian"
    local docker_cli=()
    local docker_tags=()

    # Set type
    docker_cli+=("--label" "io.hass.type=base")
    docker_cli+=("--label" "io.hass.base.version=$RELEASE")
    docker_cli+=("--label" "io.hass.base.name=debian")
    docker_cli+=("--label" "io.hass.base.image=$DOCKER_HUB/$image")

    # Start build
    run_build "$TARGET/$build_arch" "$DOCKER_HUB" "$image" "$VERSION" \
        "$build_from" "$build_arch" docker_cli[@] docker_tags[@]
}


function build_base_raspbian_image() {
    local build_arch=$1

    local build_from="$VERSION"
    local image="{arch}-base-raspbian"
    local docker_cli=()
    local docker_tags=()

    # Select builder image
    if [ "$build_arch" != "armhf" ]; then
        bashio::log.error "$build_arch not supported for raspbian"
        return 1
    fi

    # Set type
    docker_cli+=("--label" "io.hass.type=base")
    docker_cli+=("--label" "io.hass.base.version=$RELEASE")
    docker_cli+=("--label" "io.hass.base.name=raspbian")
    docker_cli+=("--label" "io.hass.base.image=$DOCKER_HUB/$image")

    # Start build
    run_build "$TARGET" "$DOCKER_HUB" "$image" "$VERSION" \
        "$build_from" "$build_arch" docker_cli[@] docker_tags[@]
}


function build_addon() {
    local build_arch=$1

    local build_from=""
    local version=""
    local image=""
    local repository=""
    local raw_image=""
    local name=""
    local description=""
    local url=""
    local args=""
    local docker_cli=()
    local docker_tags=()

    # Read addon build.json
    if [ -f "$TARGET/build.json" ]; then
        build_from="$(jq --raw-output ".build_from.$build_arch // empty" "$TARGET/build.json")"
        args="$(jq --raw-output '.args // empty | keys[]' "$TARGET/build.json")"
    fi

    # Set defaults build things
    if [ -z "$build_from" ]; then
        build_from="homeassistant/${build_arch}-base:latest"
    fi

    # Additional build args
    if [ -n "$args" ]; then
        for arg in $args; do
            value="$(jq --raw-output ".args.$arg" "$TARGET/build.json")"
            docker_cli+=("--build-arg" "$arg=$value")
        done
    fi

    # Read addon config.json
    name="$(jq --raw-output '.name // empty' "$TARGET/config.json" | sed "s/'//g")"
    description="$(jq --raw-output '.description // empty' "$TARGET/config.json" | sed "s/'//g")"
    url="$(jq --raw-output '.url // empty' "$TARGET/config.json")"
    version="$(jq --raw-output '.version' "$TARGET/config.json")"
    raw_image="$(jq --raw-output '.image // empty' "$TARGET/config.json")"
    mapfile -t supported_arch < <(jq --raw-output '.arch // empty' "$TARGET/config.json")

    # Check arch
    if [[ ! ${supported_arch[*]} =~ ${build_arch} ]]; then
        bashio::log.error "$build_arch not supported for this add-on"
        return 1
    fi

    # Read data from image
    if [ -n "$raw_image" ]; then
        repository="$(echo "$raw_image" | cut -f 1 -d '/')"
        image="$(echo "$raw_image" | cut -f 2 -d '/')"
    fi

    # Set additional labels
    docker_cli+=("--label" "io.hass.name=$name")
    docker_cli+=("--label" "io.hass.description=$description")
    docker_cli+=("--label" "io.hass.type=addon")

    if [ -n "$url" ]; then
        docker_cli+=("--label" "io.hass.url=$url")
    fi

    # Start build
    run_build "$TARGET" "$repository" "$image" "$version" \
        "$build_from" "$build_arch" docker_cli[@] docker_tags[@]
}


function build_generic() {
    local build_arch=$1

    local build_from=""
    local image=""
    local repository=""
    local raw_image=""
    local version_tag=false
    local args=""
    local docker_cli=()
    local docker_tags=()

    # Read build.json
    if [ -f "$TARGET/build.json" ]; then
        build_from="$(jq --raw-output ".build_from.$build_arch // empty" "$TARGET/build.json")"
        args="$(jq --raw-output '.args // empty | keys[]' "$TARGET/build.json")"
        labels="$(jq --raw-output '.labels // empty | keys[]' "$TARGET/build.json")"
        raw_image="$(jq --raw-output '.image // empty' "$TARGET/build.json")"
        version_tag="$(jq --raw-output '.version_tag // false' "$TARGET/build.json")"
    fi

    # Set defaults build things
    if [ -z "$build_from" ]; then
        bashio::log.error "$build_arch not supported for this build"
        return 1
    fi

    # Read data from image
    if [ -z "$raw_image" ]; then
        bashio::log.error "Can't find the image tag on build.json"
        return 1
    fi
    repository="$(echo "$raw_image" | cut -f 1 -d '/')"
    image="$(echo "$raw_image" | cut -f 2 -d '/')"

    # Additional build args
    if [ -n "$args" ]; then
        for arg in $args; do
            value="$(jq --raw-output ".args.$arg" "$TARGET/build.json")"
            docker_cli+=("--build-arg" "$arg=$value")
        done
    fi

    # Additional build labels
    if [ -n "$labels" ]; then
        for label in $labels; do
            value="$(jq --raw-output ".labels.\"$label\"" "$TARGET/build.json")"
            docker_cli+=("--label" "$label=$value")
        done
    fi

    # Version Tag
    if [ "$version_tag" == "true" ]; then
        if [[ "$VERSION" =~ d ]]; then
            docker_tags+=("dev")
        elif [[ "$VERSION" =~ b ]]; then
            docker_tags+=("beta")
        else
            docker_tags+=("stable")
        fi
    fi

    # Start build
    run_build "$TARGET" "$repository" "$image" "$VERSION" \
        "$build_from" "$build_arch" docker_cli[@] docker_tags[@]
}


function build_homeassistant_machine() {
    local build_machine=$1

    local image="${build_machine}-homeassistant"
    local dockerfile="$TARGET/$build_machine"
    local build_from=""
    local docker_cli=()
    local docker_tags=()

    # Set labels
    docker_cli+=("--label" "io.hass.machine=$build_machine")
    docker_cli+=("--file" "$dockerfile")

    # Add additional tag
    if [[ "$VERSION" =~ d ]]; then
        docker_tags+=("dev")
    elif [[ "$VERSION" =~ b ]]; then
        docker_tags+=("beta")
    else
        docker_tags+=("stable")
    fi

    # Start build
    run_build "$TARGET" "$DOCKER_HUB" "$image" "$VERSION" \
        "$build_from" "" docker_cli[@] docker_tags[@]
}


function build_homeassistant_landingpage() {
    local build_machine=$1
    local build_arch=$2

    local image="${build_machine}-homeassistant"
    local build_from="homeassistant/${build_arch}-base:latest"
    local docker_cli=()
    local docker_tags=()

    # Set labels
    docker_cli+=("--label" "io.hass.machine=$build_machine")
    docker_cli+=("--label" "io.hass.type=landingpage")

    # Start build
    run_build "$TARGET" "$DOCKER_HUB" "$image" "$VERSION" \
        "$build_from" "$build_arch" docker_cli[@] docker_tags[@]
}


function build_wheels() {
    local build_arch=$1

    local version=""
    local image="{arch}-wheels"
    local build_from="homeassistant/${build_arch}-base-python:${PYTHON}"
    local docker_cli=()
    local docker_tags=()

    # Read version
    if [ "$VERSION" == "dev" ]; then
        version="dev"
    else
        version="$(python3 "$TARGET/setup.py" -V)"
    fi

    # If latest python version/build
    if [ "$RELEASE_TAG" == "true" ]; then
        docker_tags=("$version")
    fi

    # Metadata
    docker_cli+=("--label" "io.hass.type=wheels")

    # Start build
    run_build "$TARGET" "$DOCKER_HUB" "$image" "$version-${PYTHON}" \
        "$build_from" "$build_arch" docker_cli[@] docker_tags[@]
}


function extract_machine_build() {
    local list=$1
    local array=()
    local remove=()

    if [ "$list" != "ALL" ]; then
        IFS="," read -ra array <<<"$list"
        for i in "${!BUILD_MACHINE[@]}"; do
            skip=
            for j in "${array[@]}"; do
                [[ $i == "$j" ]] && { skip=1; break; }
            done
            [[ -n $skip ]] || remove+=("$i")
        done

        for i in "${remove[@]}"; do
            unset BUILD_MACHINE["$i"]
        done
    fi
}

#### initialized cross-build ####

function init_crosscompile() {
    bashio::log.info "Setup crosscompiling feature"
    (
        mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc
        update-binfmts --enable qemu-arm
        update-binfmts --enable qemu-aarch64
    ) > /dev/null 2>&1 || bashio::log.warning "Can't enable crosscompiling feature"
}


function clean_crosscompile() {
    if [ "$CROSSBUILD_CLEANUP" == "false" ]; then
        bashio::log.info "Skeep crosscompiling cleanup"
        return 0
    fi

    bashio::log.info "Clean crosscompiling feature"
    if [ -f /proc/sys/fs/binfmt_misc ]; then
        umount /proc/sys/fs/binfmt_misc || true
    fi

    (
        update-binfmts --disable qemu-arm
        update-binfmts --disable qemu-aarch64
    ) > /dev/null 2>&1 || bashio::log.warning "No crosscompiling feature found for cleanup"
}

#### Error handling ####

function error_handling() {
    stop_docker
    clean_crosscompile

    bashio::exit.nok "Abort by User"
}
trap 'error_handling' SIGINT SIGTERM

#### Parse arguments ####

while [[ $# -gt 0 ]]; do
    key=$1
    case $key in
        -h|--help)
            print_help
            ;;
        -r|--repository)
            GIT_REPOSITORY=$2
            shift
            ;;
        -b|--branch)
            GIT_BRANCH=$2
            shift
            ;;
        -t|--target)
            TARGET=$2
            shift
            ;;
        -v|--version)
            VERSION=$2
            shift
            ;;
        --release)
            RELEASE=$2
            shift
            ;;
        -i|--image)
            IMAGE=$2
            shift
            ;;
        --no-latest)
            DOCKER_LATEST=false
            ;;
        --test)
            DOCKER_PUSH=false
            ;;
        --no-cache)
            DOCKER_CACHE=false
            ;;
        --self-cache)
            SELF_CACHE=true
            ;;
        --cache-tag)
            CUSTOM_CACHE_TAG=$2
            shift
            ;;
        --release-tag)
            RELEASE_TAG=true
            ;;
        -d|--docker-hub)
            DOCKER_HUB=$2
            shift
            ;;
        --docker-hub-check)
            DOCKER_HUB_CHECK=true
            ;;
        --docker-user)
            DOCKER_USER=$2
            shift
	    ;;
        --docker-password)
            DOCKER_PASSWORD=$2
            shift
	    ;;
        --no-crossbuild-cleanup)
            CROSSBUILD_CLEANUP=false
            ;;
        --armhf)
            BUILD_LIST+=("armhf")
            ;;
        --armv7)
            BUILD_LIST+=("armv7")
            ;;
        --amd64)
            BUILD_LIST+=("amd64")
            ;;
        --i386)
            BUILD_LIST+=("i386")
            ;;
        --aarch64)
            BUILD_LIST+=("aarch64")
            ;;
        --all)
            BUILD_LIST=("armhf" "armv7" "amd64" "i386" "aarch64")
            ;;
        --addon)
            BUILD_TYPE="addon"
            ;;
        --base)
            BUILD_TYPE="base"
            SELF_CACHE=true
            VERSION=$2
            shift
            ;;
        --base-python)
            BUILD_TYPE="base-python"
            SELF_CACHE=true
            VERSION="$(echo "$2" | cut -d '=' -f 1)"
            ALPINE="$(echo "$2" | cut -d '=' -f 2)"
            shift
            ;;
        --base-ubuntu)
            BUILD_TYPE="base-ubuntu"
            SELF_CACHE=true
            VERSION=$2
            shift
            ;;
        --base-debian)
            BUILD_TYPE="base-debian"
            SELF_CACHE=true
            VERSION=$2
            shift
            ;;
        --base-raspbian)
            BUILD_TYPE="base-raspbian"
            SELF_CACHE=true
            VERSION=$2
            shift
            ;;
        --generic)
            BUILD_TYPE="generic"
            VERSION=$2
            shift
            ;;
        --homeassistant-landingpage)
            BUILD_TYPE="homeassistant-landingpage"
            SELF_CACHE=true
            DOCKER_LATEST=false
            VERSION="landingpage"
            extract_machine_build "$2"
            shift
            ;;
        --homeassistant-machine)
            BUILD_TYPE="homeassistant-machine"
            SELF_CACHE=true
            VERSION="$(echo "$2" | cut -d '=' -f 1)"
            extract_machine_build "$(echo "$2" | cut -d '=' -f 2)"
            shift
            ;;
        --builder-wheels)
            BUILD_TYPE="builder-wheels"
            PYTHON=$2
            SELF_CACHE=true
            shift
            ;;

        *)
            bashio::exit.nok "$0 : Argument '$1' unknown"
            ;;
    esac
    shift
done

# Check if an architecture is available
if [ "${#BUILD_LIST[@]}" -eq 0 ] && ! [[ "$BUILD_TYPE" =~ ^homeassistant-(machine|landingpage)$ ]]; then
    bashio::exit.nok "You need select an architecture for build!"
fi

# Check other args
if [ "$BUILD_TYPE" != "addon" ] && [ "$BUILD_TYPE" != "generic" ] && [ -z "$DOCKER_HUB" ]; then
    bashio::exit.nok "Please set a docker hub!"
fi


#### Main ####

mkdir -p /data

# Setup docker env
init_crosscompile
start_docker

# Login into dockerhub
if [ -n "$DOCKER_USER" ] && [ -n "$DOCKER_PASSWORD" ]; then
  docker login -u "$DOCKER_USER" -p "$DOCKER_PASSWORD"
fi

# Load external repository
if [ -n "$GIT_REPOSITORY" ]; then
    bashio::log.info "Checkout repository $GIT_REPOSITORY"
    git clone --depth 1 --branch "$GIT_BRANCH" "$GIT_REPOSITORY" /data/git 2> /dev/null
    TARGET="/data/git/$TARGET"
fi

# Select arch build
if [ "${#BUILD_LIST[@]}" -ne 0 ]; then
    bashio::log.info "Run $BUILD_TYPE build for: ${BUILD_LIST[*]}"
    for arch in "${BUILD_LIST[@]}"; do
        if [ "$BUILD_TYPE" == "addon" ]; then
            (build_addon "$arch") &
        elif [ "$BUILD_TYPE" == "generic" ]; then
            (build_generic "$arch") &
        elif [ "$BUILD_TYPE" == "base" ]; then
            (build_base_image "$arch") &
        elif [ "$BUILD_TYPE" == "base-python" ]; then
            (build_base_python_image "$arch") &
        elif [ "$BUILD_TYPE" == "base-ubuntu" ]; then
            (build_base_ubuntu_image "$arch") &
        elif [ "$BUILD_TYPE" == "base-debian" ]; then
            (build_base_debian_image "$arch") &
        elif [ "$BUILD_TYPE" == "base-raspbian" ]; then
            (build_base_raspbian_image "$arch") &
        elif [ "$BUILD_TYPE" == "builder-wheels" ]; then
            (build_wheels "$arch") &
        elif [[ "$BUILD_TYPE" =~ ^homeassistant-(machine|landingpage)$ ]]; then
            continue  # Handled in the loop below
        else
            bashio::exit.nok "Invalid build type: $BUILD_TYPE"
        fi
        BUILD_TASKS+=($!)
    done
fi

# Select machine build
if [[ "$BUILD_TYPE" =~ ^homeassistant-(machine|landingpage)$ ]]; then
    bashio::log.info "Machine builds: ${!BUILD_MACHINE[*]}"
    for machine in "${!BUILD_MACHINE[@]}"; do
        machine_arch="${BUILD_MACHINE["$machine"]}"
        if [ "$BUILD_TYPE" == "homeassistant-machine" ]; then
            (build_homeassistant_machine "$machine") &
        elif [ "$BUILD_TYPE" == "homeassistant-landingpage" ]; then
            (build_homeassistant_landingpage "$machine" "$machine_arch") &
        fi
        BUILD_TASKS+=($!)
    done
fi

# Wait until all build jobs are done
wait "${BUILD_TASKS[@]}"

# Cleanup docker env
clean_crosscompile
stop_docker

# No Errors
if [ ${#BUILD_ERROR[@]} -eq 0 ]; then
    bashio::exit.ok
fi

bashio::exit.nok "Some build fails: ${BUILD_ERROR[*]}"
