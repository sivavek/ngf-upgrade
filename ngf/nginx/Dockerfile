# This is deliberately a contract-only scaffold.
#
# The NGF data plane must be rebuilt for hardened Ubuntu with the exact NGF
# release-compatible NGINX, NGINX Agent, NJS and OpenTelemetry packages. Do not
# replace this with a generic NGINX container: it must retain NGF's configuration
# files, /agent/entrypoint.sh, non-root UID/GID 101:1001, and writable runtime
# paths. Package sources, signatures, checksums, and versions must be approved
# before implementation.

ARG HARDENED_UBUNTU_IMAGE
FROM ${HARDENED_UBUNTU_IMAGE}

ARG NGINX_VERSION
ARG NGINX_AGENT_VERSION

RUN test -n "${NGINX_VERSION}" \
    && test -n "${NGINX_AGENT_VERSION}" \
    && echo 'NGF data-plane package provenance must be implemented before this image can be built.' >&2 \
    && exit 1
