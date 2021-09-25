ARG BUILD_FROM
FROM $BUILD_FROM


# Setup locals
ENV \
    VCN_OTP_EMPTY=true \
    LANG=C.UTF-8

ARG \
    BUILD_ARCH \
    VCN_VERSION \
    YQ_VERSION

RUN \
    set -x \
    && apk add --no-cache \
        git \
        docker \
        coreutils \
    && apk add --no-cache --virtual .build-dependencies \
        build-base \
        go \
    \
    && git clone -b v${VCN_VERSION} --depth 1 \
        https://github.com/codenotary/vcn \
    && cd vcn \
    \
    && if [ "${BUILD_ARCH}" = "armhf" ]; then \
        GOARM=6 GOARCH=arm go build -o vcn -ldflags="-s -w" ./cmd/vcn; \
    elif [ "${BUILD_ARCH}" = "armv7" ]; then \
        GOARM=7 GOARCH=arm go build -o vcn -ldflags="-s -w" ./cmd/vcn; \
    elif [ "${BUILD_ARCH}" = "aarch64" ]; then \
        GOARCH=arm64 go build -o vcn -ldflags="-s -w" ./cmd/vcn; \
    elif [ "${BUILD_ARCH}" = "i386" ]; then \
        GOARCH=386 go build -o vcn -ldflags="-s -w" ./cmd/vcn; \
    elif [ "${BUILD_ARCH}" = "amd64" ]; then \
        GOARCH=amd64 go build -o vcn -ldflags="-s -w" ./cmd/vcn; \
    else \
        exit 1; \
    fi \
    \
    && rm -rf /root/go /root/.cache \
    && mv vcn /usr/bin/vcn \
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
    && rm -rf /usr/src/vcn

COPY builder.sh /usr/bin/

WORKDIR /data
ENTRYPOINT ["/usr/bin/builder.sh"]
