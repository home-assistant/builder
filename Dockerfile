ARG BUILD_FROM
FROM $BUILD_FROM

ARG \
    BUILD_ARCH \
    YQ_VERSION \
    COSIGN_VERSION

RUN \
    set -x \
    && apk add --no-cache \
        git \
        docker \
        docker-cli-buildx \
        coreutils \
    \
    && if [ "${BUILD_ARCH}" = "armhf" ] || [ "${BUILD_ARCH}" = "armv7" ]; then \
        wget -q -O /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_arm"; \
        wget -q -O /usr/bin/cosign "https://github.com/home-assistant/cosign/releases/download/${COSIGN_VERSION}/cosign_armhf"; \
    elif [ "${BUILD_ARCH}" = "aarch64" ]; then \
        wget -q -O /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_arm64"; \
        wget -q -O /usr/bin/cosign "https://github.com/home-assistant/cosign/releases/download/${COSIGN_VERSION}/cosign_aarch64"; \
    elif [ "${BUILD_ARCH}" = "i386" ]; then \
        wget -q -O /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_386"; \
        wget -q -O /usr/bin/cosign "https://github.com/home-assistant/cosign/releases/download/${COSIGN_VERSION}/cosign_i386"; \
    elif [ "${BUILD_ARCH}" = "amd64" ]; then \
        wget -q -O /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"; \
        wget -q -O /usr/bin/cosign "https://github.com/home-assistant/cosign/releases/download/${COSIGN_VERSION}/cosign_amd64"; \
    else \
        exit 1; \
    fi \
    && git config --global --add safe.directory "*" \
    && chmod +x /usr/bin/yq \
    && chmod +x /usr/bin/cosign

COPY builder.sh /usr/bin/

WORKDIR /data
ENTRYPOINT ["/usr/bin/builder.sh"]
