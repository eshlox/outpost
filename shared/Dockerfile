# outpost base image: Ubuntu + your terminal tools + default dotfiles.
#
# Keep this the single place your TOOLS live. Your dotfiles are baked at
# /etc/outpost-skel (from shared/home/) and copied into /home/ubuntu by bootstrap-user.sh
# on each setup/update. Node + Claude/Codex are installed into the per-project
# /home/ubuntu VOLUME by bootstrap so they persist and self-update; only system
# tools are baked here so `outpost update` refreshes them.
#
# Pinned tool versions are ARGs so they are reproducible and easy to bump.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Container timezone. Override at build time: `outpost base` builds the shared image,
# so set it via OUTPOST_TZ in your config (or `docker build --build-arg TZ=...`).
ARG TZ=UTC

# Keep apt's downloaded .debs and package lists so the BuildKit cache mounts below actually
# persist them across builds (Ubuntu's docker-clean hook deletes debs otherwise). The apt
# RUNs mount /var/cache/apt + /var/lib/apt/lists as caches (build-time only, never in the
# final image), so repeated `outpost base`/`update` skip the re-download. Needs BuildKit
# (outpost forces DOCKER_BUILDKIT=1); no `rm -rf .../lists` needed - the mount isn't baked.
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
  && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Base OS packages. ripgrep/fd/bat/jq for you and your agents; socat for the agent
# bridge; direnv for per-project env; tmux is the multiplexer outpost uses for session
# survival via `outpost sh` (Ubuntu's 3.4 is recent enough; no need for a tarball).
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      bash bash-completion ca-certificates curl wget git openssh-client socat less \
      build-essential pkg-config ripgrep fd-find bat jq unzip xz-utils gnupg \
      procps direnv locales tmux tzdata \
  && ln -sf "$(command -v fdfind)" /usr/local/bin/fd \
  && ln -sf "$(command -v batcat)" /usr/local/bin/bat \
  && sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen \
  && ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime \
  && echo "${TZ}" >/etc/timezone \
  && dpkg-reconfigure -f noninteractive tzdata
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV TZ=${TZ}

# Map dpkg arch -> the naming each release uses. Used by the tool installs below.
RUN set -eux; arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      arm64) echo aarch64 >/tmp/uarch; echo arm64 >/tmp/garch ;; \
      amd64) echo x86_64  >/tmp/uarch; echo x86_64 >/tmp/garch ;; \
      *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac

# Tools not in the Ubuntu repos (or too old there) come from pinned GitHub release
# tarballs over HTTPS. TLS is the integrity guarantee; a same-source checksum adds
# no provenance, so we just `curl | tar`. Bump the ARG to update a tool.

# Helix editor.
ARG HELIX_VERSION=25.07.1
RUN set -eux; u="$(cat /tmp/uarch)"; \
    curl -fSL "https://github.com/helix-editor/helix/releases/download/${HELIX_VERSION}/helix-${HELIX_VERSION}-${u}-linux.tar.xz" -o /tmp/hx.tar.xz; \
    mkdir -p /opt/helix && tar -xJf /tmp/hx.tar.xz -C /opt/helix --strip-components=1; \
    ln -sf /opt/helix/hx /usr/local/bin/hx; \
    mkdir -p /usr/local/share/helix && cp -r /opt/helix/runtime /usr/local/share/helix/runtime; \
    rm -f /tmp/hx.tar.xz
ENV HELIX_RUNTIME=/usr/local/share/helix/runtime

# lazygit. NOTE: the asset name uses lowercase 'linux' on current releases
# (it was capital 'Linux' before ~v0.45); keep it lowercase when bumping.
ARG LAZYGIT_VERSION=0.62.2
RUN set -eux; g="$(cat /tmp/garch)"; \
    curl -fSL "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_linux_${g}.tar.gz" -o /tmp/lg.tar.gz; \
    tar -xzf /tmp/lg.tar.gz -C /usr/local/bin lazygit; rm -f /tmp/lg.tar.gz

# git-delta. The release triple prefix is exactly /tmp/uarch (aarch64/x86_64).
ARG DELTA_VERSION=0.19.2
RUN set -eux; u="$(cat /tmp/uarch)"; \
    curl -fSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${u}-unknown-linux-gnu.tar.gz" -o /tmp/delta.tar.gz; \
    tar -xzf /tmp/delta.tar.gz -C /tmp; \
    install -m0755 /tmp/delta-*/delta /usr/local/bin/delta; rm -rf /tmp/delta*

# fzf (zshrc uses `fzf --zsh`, which needs fzf >= 0.48). NOTE: fzf names its linux
# assets with the DPKG arch (amd64/arm64), not garch's x86_64.
ARG FZF_VERSION=0.73.1
RUN set -eux; a="$(dpkg --print-architecture)"; \
    curl -fSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${a}.tar.gz" -o /tmp/fzf.tar.gz; \
    tar -xzf /tmp/fzf.tar.gz -C /usr/local/bin fzf; rm -f /tmp/fzf.tar.gz

# starship (prompt) - musl build for both arches.
ARG STARSHIP_VERSION=1.25.1
RUN set -eux; u="$(cat /tmp/uarch)"; \
    curl -fSL "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${u}-unknown-linux-musl.tar.gz" -o /tmp/starship.tar.gz; \
    tar -xzf /tmp/starship.tar.gz -C /usr/local/bin starship; rm -f /tmp/starship.tar.gz

# just (task runner; your bashrc has a `just` wrapper + global justfile). Note: no
# leading 'v' in just's tag.
ARG JUST_VERSION=1.52.0
RUN set -eux; u="$(cat /tmp/uarch)"; \
    curl -fSL "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-${u}-unknown-linux-musl.tar.gz" -o /tmp/just.tar.gz; \
    tar -xzf /tmp/just.tar.gz -C /usr/local/bin just; rm -f /tmp/just.tar.gz

# herdr (terminal multiplexer for running several coding agents from one session -
# a natural fit for the box, which is built to run agents). Ships a raw per-arch
# binary (no tarball); its asset arch names are exactly /tmp/uarch (aarch64/x86_64).
# Tag has a leading 'v'. Verify with `herdr --version` after `outpost base`.
ARG HERDR_VERSION=0.7.5
RUN set -eux; u="$(cat /tmp/uarch)"; \
    curl -fSL "https://github.com/ogulcancelik/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-${u}" -o /tmp/herdr; \
    install -m0755 /tmp/herdr /usr/local/bin/herdr; rm -f /tmp/herdr

# GitHub CLI (apt repo).
RUN set -eux; \
    mkdir -p -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null; \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      >/etc/apt/sources.list.d/github-cli.list
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends gh

# cloudflared (Cloudflare apt repo) - used for `cf` quick tunnels (Expo phone testing).
RUN set -eux; \
    mkdir -p --mode=0755 /usr/share/keyrings; \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
      | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null; \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
      >/etc/apt/sources.list.d/cloudflared.list
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends cloudflared

# Headless-browser SYSTEM LIBRARIES for frontend testing (Playwright/Puppeteer, and
# `flutter test --platform chrome`). We bake the shared OS deps here - stable, apt-
# managed, refreshed by `outpost update` - but NOT a browser binary: each project
# fetches its own version-pinned Chromium into the /home/ubuntu VOLUME with
# `npx playwright install chromium`, so the browser tracks the repo's Playwright
# version and persists/self-updates like Node (see the base-image philosophy up top).
# Playwright's bundled Chromium is cross-arch (arm64 + amd64); a Google Chrome .deb is
# not, which is why we do NOT apt-install a browser (Ubuntu 24.04's `chromium` apt
# package is a snapd stub that can't run in a container anyway).
#
# Library list is Playwright's own chromium dep set for ubuntu24.04 (note the t64
# names from the time_t transition); source of truth is playwright-core's nativeDeps.
# Fonts: liberation (core Latin metrics), noto-color-emoji, unifont (broad glyph
# coverage) - a lean subset of Playwright's font list, enough for readable rendering
# and screenshots without pulling every CJK/Thai pack.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 \
      libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 \
      libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 \
      libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
      fonts-liberation fonts-noto-color-emoji fonts-unifont

# Pin GitHub's SSH host keys - all three types, since different clients/tools negotiate a
# different host-key algorithm (ed25519, ecdsa, or rsa) and only trust the matching pin.
# Verify these against GitHub's published fingerprints before relying on them, and bump if
# GitHub ever rotates them:
# https://docs.github.com/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
RUN mkdir -p /etc/ssh && printf '%s\n' \
  'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' \
  'github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=' \
  'github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4xcI=' \
  >> /etc/ssh/ssh_known_hosts

# Use Ubuntu 24.04's built-in non-root 'ubuntu' user (uid/gid 1000, bash shell).
# No custom user, no uid juggling. No passwordless sudo by default (see security.md).
RUN mkdir -p /workspace && chown ubuntu:ubuntu /workspace

# Dotfiles. The shipped defaults live in shared/home/ (tasteful + neutral); point
# OUTPOST_DOTFILES_DIR at your own and outpost overlays them on top (see bin/outpost).
# Baked into /etc/outpost-skel; outpost-bootstrap-user copies them into /home/ubuntu on
# each setup/update (so edits re-apply, sidestepping the home-volume staleness gotcha).
COPY home/ /etc/outpost-skel/

# The user bootstrap (apply dotfiles + node + Claude/Codex/opencode/hunk). Runs on setup/update.
COPY bootstrap-user.sh /usr/local/bin/outpost-bootstrap-user
RUN chmod +x /usr/local/bin/outpost-bootstrap-user

# Mutagen sshd helper, baked into EVERY image so projects opt in WITHOUT vendoring
# the script - a project just installs openssh-server (see examples/mutagen-sshd).
# openssh-server itself is intentionally NOT in the base (kept lean; client only);
# the .bashrc runs `outpost-sshd --ensure` only where sshd is actually installed.
COPY sshd.sh /usr/local/bin/outpost-sshd
RUN chmod +x /usr/local/bin/outpost-sshd

# A project's own services (Postgres/Redis/...) run on the HOST Docker engine via
# `outpost up`, reachable from the container by name on the project network - so the
# base image carries no Docker engine and the container never gets the host socket.
# See docs/services.md.

USER ubuntu
WORKDIR /workspace
# fnm (node), npm globals, and local bins live in the persistent /home/ubuntu volume.
ENV PATH="/home/ubuntu/.local/bin:/home/ubuntu/.local/share/fnm:/home/ubuntu/.npm-global/bin:${PATH}"
# outpost exec's in without login/PAM, so SHELL would otherwise be unset; pin bash so
# tmux opens bash panes (tab-completion + starship), not /bin/sh.
ENV SHELL=/bin/bash
# Advertise truecolor + a terminfo that always exists. Neither ssh nor docker exec
# carries COLORTERM in, and docker exec -it stamps a bare TERM=xterm (8 colors), so
# without this chalk/Claude/Codex detect 8/256 colors and quantize their orange
# logo to red. COLORTERM must be exactly "truecolor" (chalk ignores "24bit"); it
# wins over the TERM=*-256color cap. tmux inherits COLORTERM into its panes and
# (with terminal-features RGB, see tmux.conf) passes the 24-bit escapes through to
# Ghostty unchanged, so this is the only place the signal needs to be set.
ENV COLORTERM=truecolor
ENV TERM=xterm-256color
CMD ["sleep", "infinity"]
