# This Dockerfile is a build contract, not an approved publishing definition.
# The final base must be the Cisco-hardened Ubuntu image produced by the Packer
# process. The build context must include upstream-ngf/ at NGF_VERSION.

ARG HARDENED_UBUNTU_IMAGE
FROM golang:1.26 AS builder

WORKDIR /src
COPY upstream-ngf/go.mod upstream-ngf/go.sum ./
RUN go mod download
COPY upstream-ngf/ ./
RUN make build

FROM ${HARDENED_UBUNTU_IMAGE}

RUN groupadd --gid 1001 nginx \
    && useradd --system --uid 101 --gid 1001 --home /var/cache/nginx \
       --shell /usr/sbin/nologin nginx \
    && test -r /etc/ssl/certs/ca-certificates.crt

COPY --from=builder --chown=101:1001 /src/build/out/gateway /usr/bin/gateway
COPY --from=builder --chown=101:1001 /src/LICENSE /licenses/LICENSE

USER 101:1001
ENTRYPOINT ["/usr/bin/gateway"]
