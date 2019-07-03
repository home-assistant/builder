ARG BUILD_FROM
FROM $BUILD_FROM

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Setup locals
RUN apt-get update && apt-get install -y --no-install-recommends \
        jq \
        git \
        python3-setuptools \
    && rm -rf /var/lib/apt/lists/* \
ENV LANG C.UTF-8

# Install docker
# https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/
RUN apt-get update && apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        curl \
        software-properties-common \
        gpg-agent \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
    && add-apt-repository "deb https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce \
        docker-ce-cli \
        containerd.io \
    && rm -rf /var/lib/apt/lists/*

# Setup arm binary support
ARG BUILD_ARCH
RUN if [ "$BUILD_ARCH" != "amd64" ]; then exit 0; else \
    apt-get update && apt-get install -y --no-install-recommends \
        qemu-user-static \
        binfmt-support \
    && rm -rf /var/lib/apt/lists/*; fi

COPY builder.sh /usr/bin/

WORKDIR /data
ENTRYPOINT ["/usr/bin/builder.sh"]
