---
title: Quickstart
description: From zero to working in a container in a few minutes.
---

Assumes you've [installed outpost](/installation/) on your host and can `ssh -A dev-box`.

## 1. Set up your projects directory

Your project configs live in **your own** directory and git repo (default
`~/outpost-projects`), separate from the tool:

```sh
outpost projects init --remote git@github.com:you/outpost-projects.git
```

This creates the dir, runs `git init`, sets the remote, and drops a starter `example`
project. (`--remote` is optional — add one later or never.)

## 2. Create a project

```sh
outpost projects new web -t node     # scaffold web/ from the node template
outpost projects edit web            # tweak the Dockerfile (EXPOSE ports, extra packages)
```

A project is just a directory with a `Dockerfile` (`FROM outpost-base:latest`) and optional
`tunnels.json`, `compose.yaml`, `ports.pin`. Templates: `flutter`, `go`, `minimal`, `node`,
`python`, `rust`, `static` (`outpost projects templates`).

## 3. Build the base image (once)

```sh
outpost base                         # builds outpost-base: your tools + default dotfiles
```

## 4. Set up and enter the project

```sh
outpost setup web                    # build the image, start an EMPTY-workspace container
outpost sh web                       # drop into a tmux session inside the container
```

outpost clones nothing — inside the box you do the rest:

```sh
git clone <your repo> /workspace && cd /workspace
fnm install && fnm use               # Node from your repo's .node-version
pnpm install && pnpm dev
```

## 5. Reach your dev server

```sh
outpost ports web                    # prints the host port + a ready-to-paste ssh -L
# from your laptop:
ssh -A -L 3000:localhost:49xxx dev-box   # then open http://localhost:3000
```

## 6. Back up your configs

```sh
outpost projects sync                # pull --rebase, commit (auto message), push
```

## The everyday loop after that

```sh
ssh -A dev-box
outpost sh web        # reattach the same tmux session (agents still running)
# … work …
outpost update web    # rebuild on the latest base, keep your volumes
```

More: [the daily loop](/guides/daily/), [services](/guides/services/),
[tunnels](/guides/tunnels/), [git & ssh](/guides/git-and-ssh/).
