---
title: Command reference
description: Every outpost command at a glance.
---

Run `outpost` (or `outpost help`) for this list, and `outpost doctor` to preflight the host.
The canonical command is `outpost`; alias it (`alias ot=outpost`) for daily use.

## Lifecycle (act on a project's container)

| Command | What it does |
| --- | --- |
| `outpost base` | Build / rebuild the shared base image (`outpost-base`). |
| `outpost setup <project>` | First time: build images, start the container, bootstrap. |
| `outpost sh <project> [--no-agent]` | Attach into the container (a tmux session per project). `--no-agent` skips the git bridge. |
| `outpost exec <project> <cmd>…` | Run a one-off command inside the container (scriptable; no tmux). Requires it running. |
| `outpost dash [project…] [--no-agent]` | One host tmux to switch between projects (`C-a` project, `C-b` inside). |
| `outpost update <project>` \| `--all` | Rebuild on the latest base, **keeping** the volumes (swap-with-rollback). |
| `outpost up / down / ps <project>` | Start / stop / show the project's services (`compose.yaml`) on the host engine. |
| `outpost status [project]` | One-glance health (see below). With no project: a one-line summary row per project. |
| `outpost start <project>` | Start a stopped container (re-adds it to a running `dash`). |
| `outpost stop <project>` | Stop the container (removes it from a running `dash`). |
| `outpost restart <project>` | Stop then start the container (dash-aware). |
| `outpost rm <project>` | Remove the container (keeps volumes). |
| `outpost destroy <project>` | Remove the container **and** its volumes (drops project state). |
| `outpost logs <project> [-f]` | Container logs. |
| `outpost ls` | List outpost containers and their state. |
| `outpost cp <project> <src>… <dest>` | Copy host file(s) into `/workspace`, or **out** of the box (a source arg with a leading `:` is a container path — see below). |
| `outpost ports <project>` | Show the host ports the EXPOSE'd ports map to, with `ssh -L` hints. |
| `outpost doctor` | Preflight the host (docker, socat, agent, uid, compose plugin, …). |

### `outpost status`

With a project, `outpost status <project>` reports, in one glance:

- **Container state** — running / stopped / absent.
- **Image freshness** — whether the project image is built on the **current** base (fresh)
  or an older one (stale — `outpost update` to refresh).
- **Published host ports** — the `127.0.0.1` ports the EXPOSE'd ports map to.
- **Agent bridge** — alive or not (the `socat` pid + whether the socket is present).
- **Compose services** — their state, if the project has a `compose.yaml`.
- **Volume disk usage** — the `code` and `home` named volumes.

With no project it prints a one-line summary row per project. It's the daily-driver command:
it folds together what previously needed `ls` + `ports` + `ps` + `doctor`.

### `outpost cp` — copy in and out

Without any `:`-prefixed argument, `cp` behaves as before: host file(s) → `/workspace`
(`outpost cp web ~/shot.png`). To copy **out** of the box, prefix a source with `:` to mark
it as a path *inside* the container; the **last** argument is then the host destination:

```sh
outpost cp web :/workspace/dist/app.tar.gz ./       # pull a build artifact OUT to the host
outpost cp web ~/logo.png                            # push a host file IN to /workspace
```

## Project configs (`outpost projects …`)

| Command | What it does |
| --- | --- |
| `outpost projects init [--remote <url>]` | Create `OUTPOST_PROJECTS_DIR`, `git init`, set remote, add a starter project. |
| `outpost projects new <name> [-t <tpl>]` | Scaffold a new project from a template. |
| `outpost projects edit <name> [file]` | Open the project dir / one file in `$EDITOR`. |
| `outpost projects ls` | List configured projects. |
| `outpost projects rm <name> [--destroy]` | Remove the config dir (`--destroy` also drops the container + volumes). |
| `outpost projects sync [-m "msg"]` | Pull, commit (auto message), push. |
| `outpost projects templates` / `path` | List templates / print the projects dir. |

## Tool

| Command | What it does |
| --- | --- |
| `outpost upgrade` | Self-update the tool (`git pull --ff-only` in `OUTPOST_DIR`). |
| `outpost completion bash` | Print a bash completion script (`source <(outpost completion bash)`). |
| `outpost version` | Print the version. |

See [Configuration](/concepts/configuration/) for every `OUTPOST_*` variable.
