# outpost

> One hardened Docker container per project on a remote host — driven from your terminal.

[![CI](https://github.com/eshlox/outpost/actions/workflows/ci.yml/badge.svg)](https://github.com/eshlox/outpost/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-outpost.eshlox.net-0b7285.svg)](https://outpost.eshlox.net)

**outpost** runs one isolated, hardened Docker container per project on a remote Linux
host, and you work *inside* it over SSH — Helix, lazygit, tmux, and your AI agents. Your
laptop only runs the SSH client. The whole tool is one readable bash script: every step is
a plain `docker` command you can read and run by hand. No VS Code, no devcontainer spec,
no hidden lifecycle.

```sh
outpost projects new web -t node     # scaffold a project (Dockerfile + config)
outpost setup web                    # build the image, start the container
outpost sh web                       # drop into tmux inside; then clone + run your code
```

📖 **Full documentation: [outpost.eshlox.net](https://outpost.eshlox.net)**

## Why

- **A sandbox for YOLO agents.** The container *is* the security boundary — not an agent's
  permission prompt. Let AI agents and untrusted deps run wide open inside, without handing
  them your laptop, your SSH key, or your other projects. `--cap-drop ALL`,
  `no-new-privileges`, a per-project network, no host Docker socket, a fork-bomb guard.
- **Disposable containers, durable state.** The container is throwaway; your workspace and
  home (dotfiles, agent auth + history, node) live in named volumes. `outpost update`
  rebuilds on a fresh base and keeps them.
- **Your configs, your repo.** Project configs live in *your own* directory and git repo,
  separate from the tool. Manage them with `outpost projects new | edit | sync`. Update the
  tool with a clean `git pull`.
- **Git that never leaks your key.** Commits sign and authenticate through your forwarded
  SSH agent (`ssh -A`); the private key never enters the container.
- **Services + tunnels.** A project's Postgres/Redis/… run on the host engine, reachable by
  name; expose dev servers through per-project Cloudflare tunnels.
- **Readable, not magic.** A single readable bash script ([`bin/outpost`](bin/outpost)). It
  builds an image and runs a container — that's it.

## Is this for you?

outpost is opinionated. It fits if you have (or can rent) a **remote Linux host with
Docker**, you're happy **working in the terminal**, and you want **one isolated container
per project**. It assumes SSH access (Tailscale recommended) and a forwarded SSH agent for
git; macOS + [Secretive](https://github.com/maxgoedjen/secretive) makes the signing story
especially nice but any agent works. See
[Is this for you?](https://outpost.eshlox.net/is-this-for-you/).

## Install

On your remote host:

```sh
git clone https://github.com/eshlox/outpost.git ~/outpost
~/outpost/install.sh && source ~/.bashrc
outpost doctor          # preflight: docker, socat, agent, uid, compose plugin, …
```

Tip: `alias ot=outpost` for daily use. Full guide: [Installation](https://outpost.eshlox.net/installation/).

Uninstall is just as plain — `outpost destroy <project>` each project (drops its container +
volumes), then `rm ~/bin/outpost` and delete the PATH line from your rc. Full teardown
(images, state dir): [Uninstall](https://outpost.eshlox.net/installation/#uninstall).

## Quickstart

```sh
outpost projects init                # your projects dir + git repo (default ~/outpost-projects)
outpost projects new web -t node     # scaffold a project
outpost projects edit web            # tweak the Dockerfile (EXPOSE ports, packages)
outpost base                         # build the shared base image (once)
outpost setup web                    # build + start the container
outpost sh web                       # work inside (clone your repo into /workspace)
outpost ports web                    # host port + a ready ssh -L to reach your dev server
outpost projects sync                # back up your configs (pull, commit, push)
```

## How it works

```
your laptop ──ssh -A──► remote host ──► one container per project
   (ssh client,         (Docker engine,    (Helix/tmux/agents,
    forwarded agent)      the outpost CLI)   your code in /workspace)
```

A project is a directory with a `Dockerfile` (`FROM outpost-base:latest`) and optional
`tunnels.json`, `compose.yaml`, `ports.pin`. `outpost setup` builds the image and starts a
container with an **empty** `/workspace` — it clones nothing; you do that inside. Backing
services run on the host engine via `outpost up`. See
[Architecture](https://outpost.eshlox.net/concepts/architecture/).

## Commands

```
outpost base | setup | sh | exec | dash | update | up | down | ps
outpost start | stop | restart | status | rm | destroy | logs | ls | cp | ports | doctor
outpost projects init | new | edit | ls | rm | sync | templates | path
outpost upgrade | completion | version
```

Full reference: [Commands](https://outpost.eshlox.net/reference/commands/) ·
worked patterns: [`examples/`](examples/).

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The tool is one bash
script (`bin/outpost`); `bash tests/smoke.sh` runs the suite against a mock engine (no
Docker needed), and `shellcheck` keeps it clean.

## License

[MIT](LICENSE).
