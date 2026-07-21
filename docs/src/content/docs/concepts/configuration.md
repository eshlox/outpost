---
title: Configuration
description: Environment variables and the optional config file.
---

outpost needs no configuration to start — the defaults work. Everything is tunable through
environment variables, optionally set once in a config file.

## The config file

On startup, outpost sources `~/.config/outpost/config` (override the path with
`OUTPOST_CONFIG`) if it exists. It's plain shell — set any of the variables below once:

```sh
# ~/.config/outpost/config
OUTPOST_PROJECTS_DIR="$HOME/code/outpost-projects"
OUTPOST_TZ="Europe/Amsterdam"
OUTPOST_MEMORY="6g"
export EDITOR=hx
```

## Variables

| Variable | Default | What it does |
| --- | --- | --- |
| `OUTPOST_PROJECTS_DIR` | `~/outpost-projects` | Where your project configs live (your own repo). |
| `OUTPOST_DIR` | resolved from the symlink | The tool repo root. |
| `OUTPOST_DOTFILES_DIR` | shipped `shared/home` | Dotfiles baked into the base image — point at your own. |
| `OUTPOST_TEMPLATES_DIR` | `<tool>/templates` | Templates for `outpost projects new`. |
| `OUTPOST_TZ` | `UTC` | Base-image timezone (applied on `outpost base`). |
| `OUTPOST_ENGINE` | `docker` | Container engine binary (e.g. `podman` — see the caveat below). |
| `OUTPOST_MEMORY` | _(off)_ | Per-container memory cap (e.g. `4g`). |
| `OUTPOST_CPUS` | _(off)_ | Per-container CPU cap (e.g. `4`). |
| `OUTPOST_SHM_SIZE` | _(off, 64MB default)_ | Raise `/dev/shm` (e.g. `1g`) — headless Chromium/browser tests can exhaust the 64MB default and crash. |
| `OUTPOST_PIDS_LIMIT` | `4096` | Fork-bomb guard. |
| `OUTPOST_READONLY` | _(off)_ | Run the container with a read-only rootfs (`--read-only --tmpfs /tmp --tmpfs /run`); named volumes stay writable. Opt-in hardening. |
| `OUTPOST_AUTO_COMMIT` | _(off)_ | Auto-commit the projects repo on `projects new`/`rm`. |
| `OUTPOST_STATE_DIR` | `$XDG_RUNTIME_DIR/outpost` | Host-only state (the agent bridge socket). Falls back to `/tmp/outpost-<uid>` when `$XDG_RUNTIME_DIR` is unset (headless/cron logins). |
| `OUTPOST_SSH_HOST` | `dev-box` | The SSH host alias printed in the `ssh -L` hints from `outpost ports`. Set it to your own `~/.ssh/config` alias. |
| `OUTPOST_DASH_SESSION` | `boxes` | tmux session name for `outpost dash`. |
| `OUTPOST_ALLOW_UNSAFE_COMPOSE` | _(off)_ | Bypass the host-escalation lint on `outpost up`. |
| `OUTPOST_SKIP_BRIDGE` | _(off)_ | Skip the git agent bridge (observe-only sessions/tests). |
| `EDITOR` / `VISUAL` | first of `hx`/`nvim`/`vim`/`vi`/`nano` | Editor for `outpost projects edit` (host-side). |

> **`OUTPOST_ENGINE=podman` is untested.** outpost calls the engine like Docker (`docker run`,
> `docker compose`, `docker volume`, …), and a `podman` shim exposes the same surface, but
> rootless Podman and its compose provider have **not** been verified against outpost's
> hardening flags, the socat agent bridge, or the compose lint. Treat it as experimental —
> Docker CE is the supported engine.

## Using your own dotfiles

The base image ships **tasteful, neutral default** dotfiles so a fresh container has a
pleasant terminal out of the box. To use **your own**, keep them in their own repo (the
same dotfiles you use on your laptop work great), clone them on the host, and point
`OUTPOST_DOTFILES_DIR` at them — typically in your config file:

```sh
git clone git@github.com:you/dotfiles.git ~/dotfiles
echo 'OUTPOST_DOTFILES_DIR="$HOME/dotfiles/home"' >> ~/.config/outpost/config
outpost base    # rebuild the base image with your dotfiles
```

Your files are **overlaid on top of** the shipped defaults: your versions win where they
exist, and the **tool-integral bits** the defaults carry survive — the `just` tunnel
recipes (`.config/just/justfile`) and the `.bashrc` PATH/fnm/`outpost-sshd` hooks. If you
ship your **own** `.bashrc`, keep (or re-source) those hooks, or node/`fnm` and the Mutagen
helper won't initialise.

Per-user git identity belongs in `~/.config/git/local.gitconfig` inside the container — copy
the shipped `local.gitconfig.example` and fill it in (see [Git & SSH](/guides/git-and-ssh/)).

> **AI agents default to approval-first — except opencode.** The shipped Claude
> (`defaultMode: default`) and Codex (`approval_policy = "untrusted"`) configs ask for
> approval. The shipped opencode config is only a `$schema` line with **no `permission`
> block**, so opencode runs its own built-in defaults unless you add one. Because the
> container is a hardened sandbox, you can also run any of them fully autonomous — see
> [Running agents autonomously](/guides/agents/) for the opt-in.
