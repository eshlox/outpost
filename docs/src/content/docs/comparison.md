---
title: How it compares
description: An honest comparison with Dev Containers, Codespaces, Gitpod/Coder, DevPod, Distrobox, and plain tmux-over-SSH.
---

outpost occupies a specific niche: **one hardened container per project on a remote Linux
host you own, driven from a terminal, built for running AI agents YOLO**. Several tools
overlap parts of that. Here's where each is a better fit — and what outpost deliberately
does **not** do.

## At a glance

| | outpost | Dev Containers (VS Code) | GitHub Codespaces | Gitpod / Coder | DevPod | Distrobox | plain tmux-over-SSH |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Where it runs | Your remote host | Local (or a remote engine) | GitHub-hosted cloud | Vendor cloud or your infra | Any provider (local/cloud/k8s) | Your local Linux machine | Your remote host |
| Primary UI | Terminal (SSH) | VS Code GUI | VS Code / browser | Browser IDE | Your IDE, via SSH | Terminal | Terminal |
| Config format | One `Dockerfile` per project | `devcontainer.json` | `devcontainer.json` | `.gitpod.yml` / images | `devcontainer.json` | Plain images | None |
| Isolation model | Hardened container, per-project net, `cap-drop ALL` | Container (dev-focused defaults) | Container in vendor VM | Container / VM | Container / VM | **Tight host integration (low isolation)** | **None (a shell on the host)** |
| Agent-YOLO sandbox focus | **Yes, the point** | No | No | No | No | No | No |
| Host Docker socket exposed | Never | Often (docker-in-docker/mount) | Managed | Managed | Varies | N/A | N/A |
| You can read the whole tool | **Yes — one bash script** | No | No | No | No | Partly | N/A |
| Cost | A VPS you rent | Free (local) | Metered per hour | Free tier / self-host | Free (BYO infra) | Free | Free |
| Multi-arch (arm64 + amd64) | Yes | Depends on image | amd64 | Depends | Depends | Depends | N/A |

## When another tool is the better choice

- **You want a local GUI-IDE experience.** Use **VS Code Dev Containers** — outpost is
  terminal-first and runs on a remote host by design. If you like the devcontainer *spec*
  but want it on arbitrary infra with your own IDE over SSH, **DevPod** is the closest fit.
- **You want zero-setup, click-to-code in the browser.** **GitHub Codespaces** or
  **Gitpod** spin an environment from a repo with no host to run. **Coder** is the
  self-hosted, team-provisioned version of that idea.
- **You want your CLI tools to feel native on your own Linux desktop** (share the home dir,
  GPU, USB, `$DISPLAY`). **Distrobox** integrates tightly with the host on purpose — which
  is the *opposite* of outpost's isolation goal.
- **You just want persistent shells on a box.** **tmux-over-SSH** is the honest baseline —
  and outpost still uses tmux inside each container. The difference is isolation: plain
  tmux runs everything as your host user with no container boundary at all.

## What outpost deliberately does NOT do

- **No GUI / no VS Code integration.** It's SSH + terminal tools (Helix, lazygit, tmux) all
  the way down.
- **No cloud service, no accounts, no control plane.** You bring a Linux host; outpost is a
  script on it. There is nothing to sign up for.
- **No devcontainer.json / Compose orchestration of the workspace.** A project is one
  `Dockerfile`; the tool builds an image and runs one container — every step is a plain
  `docker` command you can retype. (A project's *services* can use `compose.yaml`, but those
  run separately on the host engine, linted for host-escalation.)
- **No multi-node scheduling.** No Kubernetes, no autoscaling fleet. One host, one
  container per project.
- **Not a hard security boundary against the host.** Your user is in the `docker` group
  (root-equivalent on that host), and containers share the host kernel. outpost isolates
  **projects from each other** and keeps secrets **off your laptop**; genuinely hostile code
  you must contain from the host itself belongs in a throwaway VM. See the
  [security model](/concepts/security/) for the honest limits.
- **No Windows containers.**

If that shape matches how you work, start with [Is this for you?](/is-this-for-you/) and the
[Quickstart](/quickstart/).
