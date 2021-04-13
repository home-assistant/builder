ARG BUILD_FROM
FROM $BUILD_FROM


# Setup locals
ENV \
    VCN_OTP_EMPTY=true \
    LANG=C.UTF-8

ARG BUILD_ARCH
ARG VCN_VERSION

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
    # Fix: https://github.com/codenotary/vcn/issues/131
    && go get github.com/codenotary/immudb@4cf9e2ae06ac2e6ec98a60364c3de3eab5524757 \
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
    \
    && apk del .build-dependencies \
    && rm -rf /usr/src/vcn

COPY builder.sh /usr/bin/

WORKDIR /data
ENTRYPOINT ["/usr/bin/builder.sh"]
