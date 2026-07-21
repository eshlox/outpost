---
title: Managing projects
description: How project configs live in your own repo, and the outpost projects commands.
---

Your project configs live in **your own directory and git repo** — by default
`~/outpost-projects` (`OUTPOST_PROJECTS_DIR`) — completely separate from the tool. That
separation is the point: you update the tool with a clean `git pull`, and your private
configs never live in a fork of the public repo.

## A project is just a directory of plain files

```
outpost-projects/
  web/
    Dockerfile        # required: FROM outpost-base:latest, EXPOSE <port>, extra packages
    tunnels.json      # optional: public Cloudflare routes
    compose.yaml      # optional: this project's services (Postgres/Redis/…)
    ports.pin         # optional: pin EXPOSE'd ports to fixed host ports
```

There are **no field-level commands** to edit ports or tunnels — a project is a few
readable files, and you edit them directly. That's simpler and more flexible than any flag
surface, and it matches outpost's "the tool guesses nothing" philosophy.

## You edit on the host — there is no push/pull-to-deliver

The projects dir lives **on the host**, where you already work in the terminal. You edit
`web/Dockerfile` right there and run `outpost setup web`. The host is the source of truth,
so there's no "edit on laptop → push → pull to box" loop. Git is purely for **backup,
history, and multiple hosts** — and it's a single command:

```sh
outpost projects sync           # git pull --rebase --autostash → commit (auto msg) → push
```

The commit message is generated from what changed (e.g. `add api; update web`); pass
`-m "…"` to override. Set `OUTPOST_AUTO_COMMIT=1` to also commit automatically on
`projects new`/`rm`.

## The `outpost projects` commands

| Command | What it does |
| --- | --- |
| `outpost projects init [--remote <url>]` | Create the dir, `git init`, set the remote, add a starter project. |
| `outpost projects new <name> [-t <tpl>]` | Scaffold `<name>/` from a template (`flutter`/`go`/`minimal`/`node`/`python`/`rust`/`static`). |
| `outpost projects edit <name> [file]` | Open the project dir (or one file: `dockerfile`/`tunnels`/`compose`/`ports`) in `$EDITOR`. |
| `outpost projects ls` | List configured projects (and whether each has a container). |
| `outpost projects rm <name> [--destroy]` | Remove the config dir; `--destroy` also drops the container + volumes. |
| `outpost projects sync [-m "msg"]` | Pull, commit (auto message), push. |
| `outpost projects templates` / `path` | List templates / print the projects dir. |

> `outpost projects rm` removes the **config**; the top-level `outpost rm` removes the
> **container** (keeping config and volumes). Different things, on purpose.

See [Examples](/reference/examples/) for worked `Dockerfile`/`compose.yaml`/`tunnels.json`
patterns to copy.
