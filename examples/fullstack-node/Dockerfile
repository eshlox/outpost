# Example: a Node/TypeScript monorepo (api + admin + web) with its own Postgres,
# Redis and Mailpit. FROM outpost-base, then add ONLY what the base lacks - outpost
# builds the image and starts an EMPTY workspace; you clone + install inside.
#
# The base already provides git, curl, build-essential, just, etc.; Node + pnpm are
# installed per-project into the home volume by bootstrap (fnm reads .node-version).
FROM outpost-base:latest

# openssh-server opts this project into the Mutagen loop: the `outpost-sshd` helper
# is already baked into the base image, so installing the server is all it takes -
# no script to copy. Drop openssh-server if you don't edit on your laptop + build in
# the box. See examples/mutagen-sshd/.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      postgresql-client \
      python3 \
      openssh-server \
  && rm -rf /var/lib/apt/lists/*
USER ubuntu

# Dev servers bind 0.0.0.0: api 3333, admin (Vite) 4322, web (Astro) 4323. outpost
# publishes each to a 127.0.0.1 host port - `outpost ports <name>` shows them + ssh -L.
EXPOSE 3333 4322 4323

# Postgres + Redis + Mailpit run on the HOST engine (compose.yaml here), reachable
# from this container as db:5432 / redis:6379 / mailpit:1025. See docs/services.md.
#
# After `outpost setup <name>`:
#   outpost up <name>            # start the services on the host engine
#   outpost sh <name>
#   git clone <your repo> /workspace && cd /workspace
#   fnm install && fnm use && pnpm install
#   DATABASE_URL=postgres://app:app@db:5432/app pnpm dev
