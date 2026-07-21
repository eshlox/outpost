---
title: Is this for you?
description: The opinionated stack outpost assumes, and who it fits.
---

outpost is deliberately opinionated. It's a great fit if your setup matches the grain
below — and a poor fit if it doesn't. Better to know now.

## outpost is for you if…

- You have (or can rent) a **remote Linux host** — a VPS, a home server, anything with
  Docker. outpost runs your dev environments there, not on your laptop.
- You're happy **working in the terminal**: Helix/Vim, tmux, lazygit, and CLI AI agents
  (Claude Code, Codex, opencode) — all running *inside* the container.
- You want **one isolated container per project**, with that project's services
  (Postgres, Redis, …) alongside, and the ability to blow it away and rebuild without
  losing your work.
- You like tools you can **read**. outpost is one bash script; every action is a plain
  `docker` command.
- You want the choice of **cheap ARM hosting**. Every baked-in tool ships for both
  `arm64` and `amd64`, so the base image builds and runs the same on an ARM VPS as on
  x86 — pick the host by price, not by architecture.

## What it assumes

| Piece | Why | Required? |
| --- | --- | --- |
| A remote Linux host with Docker | Where containers run | **Yes** |
| SSH access (Tailscale recommended) | You drive everything over SSH | **Yes** |
| Host user with uid 1000 | So the container's `ubuntu` user can read your forwarded agent | Recommended |
| An SSH agent with forwarding | Git inside the box signs/authenticates without the key entering it | For git |
| macOS + [Secretive](https://github.com/maxgoedjen/secretive) | Touch-ID-gated keys in the Secure Enclave | Optional (any agent works) |
| A Cloudflare account + domain | Public per-project tunnels | Optional |

The macOS/Secretive bits make the git-signing story especially nice, but any forwarded
ssh-agent works — outpost itself runs entirely on the Linux host.

> **uid 1000 caveat.** The container's `ubuntu` user is uid 1000, and the forwarded agent
> socket is mode 0600, so the host login user should also be **uid 1000** to read it (the
> first user created on Ubuntu is). If your host user isn't uid 1000, outpost warns and git
> inside the box may fail to reach the agent. The fix is to run outpost as a uid-1000 user —
> either make one the login user, or `sudo -u <uid-1000-user> -i`. Do **not** loosen the
> socket mode; that would expose your forwarded agent to other users on the host. See
> [Troubleshooting](/reference/troubleshooting/).

## It's probably *not* for you if…

- You want a local, GUI-IDE devcontainer experience (use VS Code Dev Containers).
- You can't or won't run a remote host.
- You need Windows containers, or a Kubernetes-style multi-node scheduler.

## The cost

A small always-on VPS (a few dollars a month) is enough for several projects. You SSH in,
you work, you disconnect — tmux keeps your sessions (and agents) alive in between.

Sound right? → [Installation](/installation/)
