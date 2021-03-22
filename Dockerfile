ARG BUILD_FROM
FROM $BUILD_FROM

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV \
    VCN_OTP_EMPTY=true \
    LANG=C.UTF-8

# Setup locals
RUN apt-get update && apt-get install -y --no-install-recommends \
        jq \
        git \
        curl \
        python3-setuptools \
    && bash <(curl https://getvcn.codenotary.com -L) \
    && rm -rf /var/lib/apt/lists/* \

# Install docker
# https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/
RUN apt-get update && apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        curl \
        software-properties-common \
        gpg-agent \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
    && add-apt-repository "deb https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    && apt-get update && apt-get install -y --no-install-recommends \
        docker-ce \
        docker-ce-cli \
        containerd.io \
    && rm -rf /var/lib/apt/lists/*

COPY builder.sh /usr/bin/

WORKDIR /data
ENTRYPOINT ["/usr/bin/builder.sh"]
