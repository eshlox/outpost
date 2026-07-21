# Node/TypeScript project (web app, API, monorepo, ...).
#
# Node itself is NOT installed here: bootstrap installs it per-project via fnm into
# the persistent home volume, pinned by your repo's .node-version / .nvmrc (run
# `fnm install && fnm use` after you clone). pnpm/claude/codex are installed too.
# Add only SYSTEM packages your app needs at build/runtime below.
FROM outpost-base:latest

# Example: a Postgres client + build deps some native modules want. Uncomment as needed.
# USER root
# RUN apt-get update && apt-get install -y --no-install-recommends \
#       postgresql-client \
#   && rm -rf /var/lib/apt/lists/*
# USER ubuntu

# Browser testing (Playwright/Puppeteer): the base image already carries Chromium's
# system libraries, so you only install the version-pinned browser binary into the home
# volume once per box after you clone - `npx playwright install chromium` (it persists +
# self-updates with your repo's Playwright version; no apt needed here).
#
# Two container-hardening caveats - outpost runs the box with --cap-drop ALL and
# no-new-privileges, and Ubuntu 24.04 restricts unprivileged user namespaces, so
# Chromium's sandbox can't start on its own:
#   - Launch with --no-sandbox (Playwright: chromium.launch({ args: ['--no-sandbox'] });
#     Puppeteer needs it too). Fine here: the whole box is already the sandbox.
#   - If Chromium crashes under load, raise shared memory: set OUTPOST_SHM_SIZE=1g on the
#     host (see outpost.config.example) or pass Chromium --disable-dev-shm-usage.

# Expose your dev server port(s). e.g. 3000 app, 5173 Vite, 6006 Storybook.
EXPOSE 3000

# Backing services (Postgres/Redis/...) run on the HOST engine via `outpost up`.
# Drop a compose.yaml beside this Dockerfile - see examples/fullstack-node/.
