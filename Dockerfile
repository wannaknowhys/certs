FROM docker.io/library/alpine:latest

RUN apk add --no-cache curl openssl ca-certificates tzdata \
 && mkdir -p /acme.sh /certs /opt/acme.sh

# Bundling acme.sh at build time ensures offline capability and immutable reproducibility
ARG ACME_SH_VERSION=3.1.1
RUN curl -fsSL "https://github.com/acmesh-official/acme.sh/archive/refs/tags/${ACME_SH_VERSION}.tar.gz" | tar -xz -C /tmp \
 && cp -r /tmp/acme.sh-*/* /opt/acme.sh/ \
 && rm -rf /tmp/acme.sh-* \
 && chmod +x /opt/acme.sh/acme.sh

COPY cf-ddns.sh /usr/local/bin/cf-ddns.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/cf-ddns.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
