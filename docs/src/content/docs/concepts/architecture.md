---
title: Architecture
description: How outpost's pieces fit together.
---

outpost is one bash script that orchestrates plain `docker` commands. Nothing else runs in
the background; there's no daemon and no hidden state beyond Docker objects and your files.

## The pieces

```
your laptop ──ssh -A──► remote host ──► one container per project
   (ssh client,         (Docker engine,    (Helix/tmux/agents,
    forwarded agent)      the outpost CLI)   your code in /workspace)
```

- **The base image (`outpost-base`)** — built from `shared/Dockerfile`: Ubuntu + your
  terminal tools (Helix, lazygit, fzf, ripgrep, …) + the default dotfiles. Built once with
  `outpost base`; rebuilt to pick up tool/dotfile changes.
- **A project** — a directory in your projects dir with a `Dockerfile` (`FROM
  outpost-base`) and optional `tunnels.json`, `compose.yaml`, `ports.pin`. You declare
  everything (extra packages, `EXPOSE <port>`); outpost guesses nothing.
- **A project's container** — `outpost setup <name>` builds `outpost-<name>` and runs ONE
  container with an **empty** `/workspace`. It does *not* clone or install your code — you
  `outpost sh` and do that inside.
- **Backing services** — a project's Postgres/Redis/… run on the **host engine** via
  `outpost up` (from `compose.yaml`), on the project's network, reachable from the
  container by name (`db:5432`). No host Docker socket ever enters the container.

## State: disposable container, durable volumes

Each project gets two named volumes:

- `outpost-<name>-code` → `/workspace` (your code)
- `outpost-<name>-home` → `/home/ubuntu` (dotfiles, agent auth + history, node, shell history)

The container is disposable. `outpost update` recreates it on a fresh base and **keeps both
volumes** (swap-with-rollback: the old container is only removed once the new one is up and
bootstrapped). `outpost destroy` is the only command that drops the volumes.

## The git agent bridge

Git inside the container uses your **forwarded** SSH agent. outpost runs a small `socat`
bridge that points a stable per-project socket at the current `ssh -A` session's agent, so
your key signs and authenticates **without ever entering the container**. See
[Git & SSH](/guides/git-and-ssh/) and the [security model](/concepts/security/).

## Isolation & hardening

Each container runs with `--cap-drop ALL`, `--security-opt no-new-privileges`, on a
per-project bridge network, with a `--pids-limit` fork-bomb guard and no added devices or
host sockets. Memory/CPU caps are opt-in (`OUTPOST_MEMORY`, `OUTPOST_CPUS`). A project's
`compose.yaml` is linted to refuse host-escalating settings before it runs on the host
engine.
