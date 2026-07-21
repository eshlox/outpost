---
title: Examples
description: Worked Dockerfile / compose / tunnels patterns to copy.
---

The [`examples/`](https://github.com/eshlox/outpost/tree/main/examples) directory in the
repo holds copy-pasteable, genericized patterns. Replace `<name>` with your project, and
`example.dev` / `dev-box` with your own domain and SSH host alias.

## Worked projects

- **`fullstack-node/`** — a Node/TypeScript monorepo (api + admin + web) with Postgres,
  Redis and Mailpit on the host engine, public tunnels, and pinned ports. The "everything on"
  example. (To also edit on your laptop over Mutagen, install `openssh-server` in its
  Dockerfile — the `outpost-sshd` helper is already baked into the base image.)
- **`python-worker/`** — a Python service (uv) with a full backing stack: Postgres, Redis,
  RabbitMQ, Mongo, Elasticsearch and MinIO.
- **`iac-toolbox/`** — an infra/secrets toolbox (OpenTofu + sops + age + yq). No ports, no
  services — just CLI tools against your infra repos.

## Snippets

- **`tunnels/`** — `fixed.tunnels.json` (named hostname → fixed port) and
  `dynamic.tunnels.json` (one stable URL, port chosen at run time). See
  [Tunnels](/guides/tunnels/).
- **`mutagen-sshd/`** — how to enable the base image's rootless `outpost-sshd` (install
  `openssh-server`) for editing on your laptop while building in the box. See
  [Edit on your laptop](/guides/mutagen-sync/).
- **`fullstack-node/ports.pin`** — pin EXPOSE'd ports to fixed host ports so `ssh -L`
  survives container restarts.
- **`ssh-config.example`** — the `~/.ssh/config` entry (agent forwarding) that makes git
  inside the container work without the private key ever entering the box.

## Start from a template instead

For a fresh project, scaffold from a built-in template and pull pieces from the examples:

```sh
outpost projects new web -t node     # flutter | go | minimal | node | python | rust | static
outpost projects edit web
```
