---
title: Services (Postgres/Redis)
description: Run a project's own backing services on the host engine.
---


If a project needs its own services (Postgres, Redis, ...) for local dev, they run
on the **host Docker engine**, attached to that project's network. The dev
container reaches them by name, exactly like a Compose setup - but the container
itself never gets the host Docker socket, so untrusted deps and YOLO agents inside
it cannot drive the host daemon.

This is the devcontainer model: the orchestrator (outpost) brings the services up on
the host; the workspace is a peer on the same network. Containers are visible in
`docker ps` on the host (which makes them easy to inspect and debug).

## Define the services

Put a `compose.yaml` in the project's dir on the host, beside its `Dockerfile`
(`projects/<name>/compose.yaml`). It is host-side config, not part of the app
repo. Declare its default network as the project's existing outpost network,
`outpost-<project>-net`, marked `external`:

```yaml
# projects/myapp/compose.yaml
services:
  db:
    image: postgis/postgis:16-3.4
    environment:
      POSTGRES_USER: myapp
      POSTGRES_PASSWORD: myapp
      POSTGRES_DB: myapp
    volumes: [db-data:/var/lib/postgresql/data]
    # Publish to host loopback ONLY if you want to reach it from your Mac (ssh -L).
    ports: ["127.0.0.1:5432:5432"]
  redis:
    image: redis:7
    ports: ["127.0.0.1:6379:6379"]

volumes:
  db-data:

networks:
  default:
    name: outpost-myapp-net   # the project network outpost already creates
    external: true
```

## Use it

```bash
outpost up myapp            # services up on the host engine, on outpost-myapp-net
outpost ps myapp           # show the project's services
outpost sh myapp           # into the workspace (already on that network)
outpost down myapp         # stop services (keeps their volumes)
```

`outpost up` creates the network if needed, so it works before or after `outpost setup`.
`outpost` is the only thing that talks to the host daemon; Compose tags every service
with `com.docker.compose.project=outpost-<project>`, so `outpost ps`/`outpost down` are scoped
to exactly that project.

### Safety: outpost lints the compose

Because these services run on the **host root daemon**, a compose that asked for
`privileged: true`, a host namespace (`network_mode/pid/ipc: host`), a Docker
socket or host-path bind mount (`/var/run/docker.sock`, `/`, `/proc`, ...),
dangerous `cap_add` (`SYS_ADMIN`, ...), or `security_opt` relaxations would punch
straight through the workspace isolation. `outpost up` renders the compose
(`docker compose config`) and **refuses** if it finds any of those. If you really
mean it, re-run with `OUTPOST_ALLOW_UNSAFE_COMPOSE=1`.

## How your app reaches the database

The dev container and the services share `outpost-<project>-net`, so reach them by
**service name**, unchanged from a normal Compose setup:

- `DATABASE_URL=postgres://myapp:myapp@db:5432/myapp`
- `REDIS_URL=redis://redis:6379`

To reach a service from your Mac, publish it to host loopback in `compose.yaml`
(`ports: ["127.0.0.1:5432:5432"]`) and forward it: `ssh -A -L 5432:localhost:5432
dev-box`. (App dev-server ports work the same way the container's do: `outpost ports
<project>` shows the dev container's published ports.)

## What this protects, and the honest cost

Protected: the project container has **no host Docker socket**, mounts **no host
secrets**, and is on its **own per-project network** (it cannot reach another
project's services). So the main risk - untrusted code in the workspace escalating
via the daemon - is closed: it has no path to the host daemon.

Not isolated, by design (this is the trade we accept for simplicity and
visibility):

- Services run under the **host root daemon** and are **visible in `docker ps`**
  (and to host root). They are not hidden or doubly-unprivileged.
- Cross-project isolation is **network-based** (separate `outpost-<project>-net`), not
  a separate daemon per project.
- Egress is open, like any container.

If you publish a service to host loopback, anything on the host loopback can reach
it; bind sensitive services to the network only (drop the `ports:`) and reach them
from the container by name instead.

## Why not nested rootless Docker

An earlier design ran a full rootless Docker daemon *inside* each project
container so the project's `docker compose` ran nested and hidden. It worked, but
rootless-Docker-in-Docker is fragile: it broke completely on a kernel bump (Linux
7.0 stopped honoring file capabilities at exec from an overlay rootfs, and
rejected rootless `overlay2`), and keeping it alive needed several
kernel-specific workarounds. The host-engine model above has none of that, at the
cost of the services being visible on the host. We chose visibility and
robustness. (Background on the kernel issue is in the project memory / git
history.)
