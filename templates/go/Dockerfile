# Go project (service, CLI, API).
#
# The Go toolchain is baked here into a SYSTEM path (/usr/local/go), so it survives
# the /home/ubuntu volume mount and refreshes on `outpost update`. Bump the version via
# the ARG. The module + build caches live under the persistent home volume (GOPATH /
# GOCACHE below), so deps survive rebuilds. outpost starts an EMPTY workspace; clone
# your repo and `go build` inside.
FROM outpost-base:latest

USER root
# Pinned Go toolchain over HTTPS (TLS is the integrity guarantee, matching the base
# image's other tool installs). Bump this ARG to update Go.
ARG GO_VERSION=1.24.5
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) g=amd64 ;; \
      arm64) g=arm64 ;; \
      *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fSL "https://go.dev/dl/go${GO_VERSION}.linux-${g}.tar.gz" -o /tmp/go.tgz; \
    tar -C /usr/local -xzf /tmp/go.tgz; rm -f /tmp/go.tgz; \
    ln -sf /usr/local/go/bin/go /usr/local/bin/go; \
    ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
USER ubuntu

# Caches in the home volume (persist across rebuilds; created at runtime by go). The
# toolchain itself is on PATH via the /usr/local/bin symlinks above.
ENV GOPATH=/home/ubuntu/go
ENV GOCACHE=/home/ubuntu/.cache/go-build
ENV PATH="/home/ubuntu/go/bin:${PATH}"

# Your dev server / API port (e.g. 8080). EXPOSE several if you need to.
EXPOSE 8080

# Backing services (Postgres/Redis/…) run on the HOST engine via `outpost up` — drop a
# compose.yaml beside this Dockerfile. See examples/.
