---
title: Base image & updates
description: Update tools without losing project state.
---


## The two layers

- **Base image (`outpost-base`)** holds your TOOLS (Helix, lazygit, delta, fzf,
  starship, just, bat, gh, cloudflared, the OS baseline) AND your vendored
  dotfiles baked at `/etc/outpost-skel` (from `shared/home/`). You change tools or
  dotfiles by editing `shared/Dockerfile` / `shared/home/` and rebuilding the base.
- **Home volume (`outpost-<project>-home`)** holds your applied CONFIG and stateful
  tools: the dotfiles copied in by bootstrap, node (fnm), Claude/Codex CLIs +
  their auth/history, cloudflared creds, shell history. These persist across
  container recreation.

This split is deliberate: rebuilding the base never touches your project state.

## Update tools for one project

```bash
outpost update <project>
```

This rebuilds `outpost-base` and the project image (every project **has** a
Dockerfile — it's what defines the project; outpost dies without one),
recreates the container on the fresh image, and re-runs `bootstrap-user.sh`
(re-applies the vendored dotfiles, node, Claude/Codex). The `code` and `home`
volumes are kept, so your repo, node_modules, and Claude/Codex auth all survive;
dotfiles are re-applied from `shared/home/` so edits there take effect.

## Update everything

```bash
outpost update --all
```

Rebuilds the base once, then recreates every project's container on it.

## What survives, what does not

Survives (named volumes): `/workspace` (your repo + node_modules) and `/home/ubuntu`
(dotfiles, Claude/Codex auth + history, cloudflared creds, node, shell history).

Does NOT survive: anything you installed manually with `apt` inside a running
container, edits outside `/workspace` and `/home/ubuntu`, running processes, and
container-local temp files. If a tool matters, put it in `shared/Dockerfile`
(system tool) or `shared/home/` + bootstrap (user config) - never hand-installed
in a live container.

## One gotcha: image `/home/ubuntu` vs the home VOLUME

Docker copies the image's `/home/ubuntu` into the home volume only on the FIRST
mount of an empty volume. Later changes you bake into the image's `/home/ubuntu` do
NOT propagate to existing project home volumes on update. That is exactly why
node, npm globals, Claude/Codex, AND the dotfiles are applied by
`bootstrap-user.sh` (which re-runs on every update, copying from `/etc/outpost-skel`)
instead of relying on the image's `/home/ubuntu`. Keep durable user setup in
`shared/home/` + bootstrap, not baked into the image home dir.

## Updating Claude / Codex / opencode specifically

They live in the home volume and generally self-update. To force it, run inside
the outpost: `npm i -g @anthropic-ai/claude-code@latest @openai/codex@latest opencode-ai@latest`,
or just `outpost update <project>` (bootstrap reinstalls if missing). Their auth/session
state in `~/.claude`, `~/.codex`, and `~/.local/share/opencode` is in the volume, so
you do not re-login.

## Rule of thumb

If it must outlive a rebuild, it belongs in one of: this repo (`shared/home/` for
dotfiles), `/workspace`, or a named volume. Never a live container's filesystem.
