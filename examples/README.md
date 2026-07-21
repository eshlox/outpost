# Examples

Worked, copy-pasteable patterns. A project is just a directory with a `Dockerfile`
(`FROM outpost-base:latest`) and optional `tunnels.json`, `compose.yaml`, `ports.pin`
beside it. Copy a directory into your projects dir (`outpost projects path`) and tweak,
or start from a template (`outpost projects new <name> -t node`) and pull pieces from here.

> Replace `<name>` with your project's name, and `example.dev` / `dev-box` with your
> own domain and SSH host alias.

## Worked project examples

- **[`fullstack-node/`](fullstack-node/)** — a Node/TS monorepo (api + admin + web) with
  Postgres, Redis and Mailpit on the host engine, public tunnels, and pinned ports. The
  "everything on" example. (To also edit on your laptop over Mutagen, install
  `openssh-server` in its Dockerfile — the `outpost-sshd` helper is baked into the base image.)
- **[`python-worker/`](python-worker/)** — a Python service (uv) with a full backing stack:
  Postgres, Redis, RabbitMQ, Mongo, Elasticsearch and MinIO.
- **[`iac-toolbox/`](iac-toolbox/)** — an infra/secrets toolbox (OpenTofu + sops + age + yq).
  No ports, no services — just CLI tools against your infra repos.

## Security recipes

- **[`egress-lock/`](egress-lock/)** — restrict a box's outbound network to just what dev
  needs (GitHub, npm, PyPI), everything else denied. Two approaches: a `DOCKER-USER` host
  firewall on the project network, and a tinyproxy egress-proxy sidecar with a domain
  allowlist. Defense-in-depth for the "let an agent run YOLO" workflow. See
  [`egress-lock/README.md`](egress-lock/README.md).
- **[`attack-lab/`](attack-lab/)** — a harmless, reproducible lab: run commands inside the
  box that *try* to steal your SSH key, reach the host Docker socket, read another project,
  or escalate to root — and watch each one fail. Shows the container boundary holding. See
  [`attack-lab/README.md`](attack-lab/README.md).

## Snippets

- **[`tunnels/`](tunnels/)** — per-project Cloudflare tunnel config: `fixed.tunnels.json`
  (named hostname → fixed port) and `dynamic.tunnels.json` (one stable URL, port chosen at
  run time). See [`tunnels/README.md`](tunnels/README.md).
- **[`mutagen-sshd/`](mutagen-sshd/)** — how to enable the base image's rootless `outpost-sshd`
  (install `openssh-server`) for editing on your laptop while building in the box via Mutagen.
  See [`mutagen-sshd/README.md`](mutagen-sshd/README.md).
- **`fullstack-node/ports.pin`** — pin EXPOSE'd ports to fixed host ports so `ssh -L` survives
  container restarts.
- **[`ssh-config.example`](ssh-config.example)** — the `~/.ssh/config` entry (agent forwarding)
  that makes git inside the container work without the private key ever entering the box.
