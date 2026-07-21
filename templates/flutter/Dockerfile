# Flutter project (mobile / desktop / web).
#
# Flutter itself is NOT baked here: it's installed per-project via fvm (Flutter
# Version Management, the fnm analog) into the persistent home volume, pinned by your
# repo's .fvmrc - run `fvm install` after you clone. Only the tiny fvm binary + the
# SYSTEM packages Flutter needs are added below, so the image stays slim and the SDK
# version tracks the repo (survives `outpost update`).
#
# No Android SDK / JDK: device + emulator builds happen on your laptop (pair it with
# the Mutagen loop - add openssh-server below). The box runs the headless half -
# `fvm flutter pub get` / analyze / test / codegen - which is what the agents need.
FROM outpost-base:latest

USER root
# Flutter's CLI deps. The base already carries git, curl, unzip and xz-utils; `zip`
# is the only gap (Dart/engine archive handling). To opt into the Mutagen loop (edit
# on your laptop, build in the box), add `openssh-server` to this list - the
# outpost-sshd helper is already in the base. See examples/mutagen-sshd.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      zip

# fvm: bake ONLY the ~4 MB binary, into /usr/local/bin (a SYSTEM path that's on PATH
# and isn't masked by the runtime home volume). The Flutter SDK lands in ~/fvm in the
# volume on first `fvm install`. fvm's own install.sh can't be used - it drops the
# binary in ~/fvm/bin without touching PATH and refuses system dirs.
ARG FVM_VERSION=4.1.2
RUN arch="$(dpkg --print-architecture)" \
  && case "$arch" in \
       amd64) fvm_arch=x64 ;; \
       arm64) fvm_arch=arm64 ;; \
       *) echo "unsupported arch for fvm: $arch" >&2; exit 1 ;; \
     esac \
  && curl -fsSL "https://github.com/leoafarias/fvm/releases/download/${FVM_VERSION}/fvm-${FVM_VERSION}-linux-${fvm_arch}.tar.gz" \
       | tar -xz -C /usr/local/bin --strip-components=1 fvm/fvm \
  && chmod +x /usr/local/bin/fvm

# Agent skills: the official Dart + Flutter skill sets (SKILL.md workflows for the
# agents). Listing them here makes outpost's bootstrap install them ONCE, globally,
# for every agent this box ships - claude-code, opencode, codex - via `npx skills`
# (see shared/bootstrap-user.sh). They're then ready to update:  npx skills update -g
RUN mkdir -p /etc/outpost && printf '%s\n' \
      dart-lang/skills \
      flutter/skills \
      >/etc/outpost/skills.list
USER ubuntu

# Flutter builds no long-running dev server for the mobile loop, so nothing is EXPOSE'd
# by default. For `flutter run -d web-server`, add e.g. `EXPOSE 8080` and serve on it.

# outpost does no cloning. After `outpost setup <name>`:
#   outpost sh <name>
#   git clone <your repo> /workspace && cd /workspace
#   fvm install                            # Flutter from the repo's .fvmrc, into ~/fvm
#   fvm flutter pub get                    # then analyze / test / codegen in the box
# (Use `fvm flutter` / `fvm dart`, or add .fvm/flutter_sdk/bin to PATH for the LSP.)
