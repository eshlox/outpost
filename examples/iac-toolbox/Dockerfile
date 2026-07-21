# Example: an IaC / secrets toolbox - OpenTofu + sops + age + yq + a newer jq on top
# of the base. No EXPOSE (no ports), no compose.yaml (no services), no tunnels.json:
# this project serves no traffic, it just runs CLI tools against your infra repos.
FROM outpost-base:latest

USER root
# Pinned release binaries over HTTPS (same approach as the base image). Asset names
# use the dpkg arch (amd64/arm64). Bump an ARG to update a tool.
ARG OPENTOFU_VERSION=1.11.6
ARG SOPS_VERSION=3.13.0
ARG AGE_VERSION=1.3.1
ARG YQ_VERSION=4.53.2
ARG JQ_VERSION=1.8.1
RUN set -eux; arch="$(dpkg --print-architecture)"; \
    curl -fSL "https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_linux_${arch}.tar.gz" -o /tmp/tofu.tar.gz; \
    tar -xzf /tmp/tofu.tar.gz -C /usr/local/bin tofu; \
    curl -fSL "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${arch}" -o /usr/local/bin/sops; \
    curl -fSL "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-${arch}.tar.gz" -o /tmp/age.tar.gz; \
    tar -xzf /tmp/age.tar.gz -C /usr/local/bin --strip-components=1 age/age age/age-keygen; \
    curl -fSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${arch}" -o /usr/local/bin/yq; \
    curl -fSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${arch}" -o /usr/local/bin/jq; \
    chmod 0755 /usr/local/bin/tofu /usr/local/bin/sops /usr/local/bin/age /usr/local/bin/age-keygen /usr/local/bin/yq /usr/local/bin/jq; \
    rm -f /tmp/tofu.tar.gz /tmp/age.tar.gz
USER ubuntu

# After `outpost setup <name>`:
#   outpost sh <name>
#   git clone <your infra repo> /workspace && cd /workspace && tofu init && tofu plan
# Keep your age key in the home volume (survives `outpost update`):
#   age-keygen -o ~/.config/sops/age/keys.txt   # sops reads SOPS_AGE_KEY_FILE
