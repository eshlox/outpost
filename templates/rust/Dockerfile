# Rust project (service, CLI, API).
#
# Rust is installed per-project via rustup into the persistent home volume (the fnm/uv
# analog), so the toolchain tracks your repo's rust-toolchain.toml and survives
# `outpost update`. Only the system linker/build deps are baked here; you install the
# toolchain once after cloning (see below). cargo's registry + target caches live in
# the home volume, so deps survive rebuilds.
FROM outpost-base:latest

USER root
# Most `-sys` crates want a linker + TLS headers; the base already carries
# build-essential, pkg-config and curl, so libssl-dev is the usual gap.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      libssl-dev
USER ubuntu

# rustup/cargo state lives in the home volume (persists; on PATH via this ENV). The
# toolchain is NOT baked, because the home volume masks anything written to
# /home/ubuntu at build time — install it at runtime after you clone (below).
ENV RUSTUP_HOME=/home/ubuntu/.rustup
ENV CARGO_HOME=/home/ubuntu/.cargo
ENV PATH="/home/ubuntu/.cargo/bin:${PATH}"

# Your dev server / API port (e.g. axum/actix on 8080). Adjust as needed.
EXPOSE 8080

# outpost does no cloning. After `outpost setup <name>`:
#   outpost sh <name>
#   git clone <your repo> /workspace && cd /workspace
#   curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal
#   cargo build            # a repo rust-toolchain.toml pins the exact toolchain
