ARG BUILD_FROM
FROM $BUILD_FROM

ARG \
    BUILD_ARCH \
    CAS_VERSION \
    YQ_VERSION

RUN \
    set -x \
    && apk add --no-cache \
        git \
        docker \
        docker-cli-buildx \
        coreutils \
    && apk add --no-cache --virtual .build-dependencies \
        build-base \
        go \
    \
    && git clone -b v${CAS_VERSION} --depth 1 \
        https://github.com/codenotary/cas \
    && cd cas \
    && make cas \
    && mv cas /usr/bin/cas \
    && if [ "${BUILD_ARCH}" = "armhf" ] || [ "${BUILD_ARCH}" = "armv7" ]; then \
        wget -q -O /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_arm"; \
    elif [ "${BUILD_ARCH}" = "aarch64" ]; then \
        wget -q -O /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_arm64"; \
    elif [ "${BUILD_ARCH}" = "i386" ]; then \
        wget -q -O /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_386"; \
    elif [ "${BUILD_ARCH}" = "amd64" ]; then \
        wget -q -O /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"; \
    else \
        exit 1; \
    fi \
    && chmod +x /usr/bin/yq \
    \
    && apk del .build-dependencies \
    && rm -rf /root/go /root/.cache \
    && rm -rf /usr/src/cas

COPY builder.sh /usr/bin/

WORKDIR /data
ENTRYPOINT ["/usr/bin/builder.sh"]
