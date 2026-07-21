---
title: The daily loop
description: The everyday work loop and reconnecting.
---


```bash
ssh -A dev-box            # over Tailscale
outpost sh web         # attaches the project's tmux session, refreshes the agent bridge
#   hx .   /   lazygit   /   pnpm dev   /   claude   /   codex
#   detach: Ctrl-b d  (the session and any running agent keep going)
```

Run your agents (Claude Code, Codex) inside the tmux session. Because tmux
lives in the container, a dropped connection does not kill them.

When you want one-glance health — is it running, is the image fresh on the current base,
what ports are published, is the agent bridge alive, how big are the volumes — reach for
`outpost status` (a project) or `outpost status` (no argument, a summary row per project).
It's the daily-driver command that folds together `ls` + `ports` + `ps` + `doctor`.

## Closing the laptop and reconnecting

Two separate problems, two tools:

1. Session survival - your editor/agent keep running when the link drops. Solved
   by tmux INSIDE the container. Nothing to do; it just keeps running on your host.
2. Getting back to it - reopen the laptop, Tailscale reconnects, then:

   ```bash
   ssh -A dev-box
   outpost sh web      # reattaches the SAME tmux session, re-points the agent bridge
   ```

`outpost sh` refreshes the agent bridge before attaching, so git auth/signing work
again after a reconnect (the old forwarded socket died with the old SSH session;
outpost re-points the stable in-container socket at the new one).

Why not mosh: mosh does not forward the SSH agent, so in-container git signing
would break. Stick with `ssh -A` + tmux. If you want mosh-style transparent
reconnect, test Eternal Terminal as an OUTER hop, but only keep it if
`ssh-add -l` and a signed commit still work through it.

## Viewing a dev server from your laptop

A port you `EXPOSE` in the project's Dockerfile is published to a DYNAMIC port on
the host's `127.0.0.1` (so several projects can all `EXPOSE 3000` without
colliding). `outpost ports <project>` shows the host port and a ready ssh -L:

```bash
outpost ports web
#   3000 -> 49153   reach from your laptop: ssh -A -L 3000:localhost:49153 dev-box
ssh -A -L 3000:localhost:49153 dev-box   # then open http://localhost:3000 on your laptop
```

The laptop side stays whatever you want (3000 here); only the host side is dynamic.
(`dev-box` is the default host alias; set `OUTPOST_SSH_HOST` to print your own in the hint.)

### Pinning a fixed host port (stable ssh -L)

The dynamic host port changes every time the container is recreated, so a hardcoded
`ssh -L 3000:localhost:3000` in your `~/.ssh/config` goes stale. To keep one host
port forever, list it in an optional **`ports.pin`** beside the project's Dockerfile
(`projects/<name>/ports.pin`), one container port per line (host port = same, or
`CPORT:HPORT` to remap):

```
# projects/api/ports.pin
3333    # AdonisJS API   -> host 127.0.0.1:3333
4322    # admin (Vite)
4323    # web (Astro)
```

Any EXPOSE'd port NOT listed keeps the default dynamic, collision-free host port.
The pin takes effect when the container is (re)created, not on a plain restart:

```bash
outpost rm api && outpost setup api   # recreate so the new -p flags apply
outpost ports api                        # 3333 -> 127.0.0.1:3333, ...
ssh -A -L 3333:localhost:3333 dev-box      # now stable across restarts
```

Trade-off: a pinned host port can collide if another running project pins the same
number - `docker run` then fails loudly instead of silently picking another.

To share a URL or reach it from your phone, run a cloudflared quick tunnel from
inside the container: `cloudflared tunnel --url http://localhost:3000` (see
[Mobile (Expo)](/guides/expo-mobile/)).

## Running several projects at once

Each project is its own container and tmux session. Open a terminal tab per
project (`outpost sh a`, `outpost sh b`, ...), or one window with `ssh -A dev-box` and
`outpost sh <p>` per pane. Agents in different projects cannot see each other's code,
ports, or home volume.

## Switching between projects from ONE connection (`outpost dash`)

Detaching one project's tmux and `outpost sh`-ing into another (or juggling N SSH
tabs) gets old. `outpost dash` puts a single **host** tmux around everything: one
window per project, each running `outpost sh <project>`. From one `ssh dev-box` (or
one Termius connection on iOS) you flip between projects with a keystroke, and a
single re-attach after a reconnect restores the whole workspace.

```bash
sudo apt install -y tmux     # ONE TIME on the host (outpost never installs it)
ssh -A dev-box
outpost dash                     # wrap every project that already has a container
outpost dash web api    # ...or name exactly the projects you want
outpost dash --no-agent          # for iOS/observe (forwards --no-agent to each outpost sh)
```

It nests two tmuxes without colliding by giving them different prefixes and
hiding the outer status bar, so the only visible bar is the project you're in:

```
C-a            host tmux  -> switch PROJECTS (C-a 1..0, C-a n/p, C-a d to leave)
C-b / Option+N container tmux -> windows WITHIN the current project (unchanged)
```

Mnemonic: **C-a picks the project, C-b/Option+N moves inside it.** `C-b` and your
`Option+1..0` pass straight through to the focused project; the host tmux only
ever grabs `C-a`. Detaching a project (`C-b d`) snaps back to it rather than
closing the window - you leave the dash with `C-a d`. Set `OUTPOST_DASH_SESSION` to
use a name other than `boxes`.

The host tmux is a transparent layer: it forwards the mouse to the focused
project and relays its clipboard (OSC52) up to your terminal, so mouse-drag
selection and `C-b [`, `v`, `y` still copy to your Mac through the extra layer.
It runs on its own tmux socket (`tmux -L outpost-dash`), so its prefix/clipboard
settings never touch any other tmux you run on the host.

After a reconnect, just **re-run `outpost dash`** (don't `tmux attach` by hand): each
launch re-points every project's agent bridge to your new forwarded agent and
publishes it into the dash, so git auth/signing keep working - the same
self-heal `outpost sh` does. Skip that and the long-lived dash stays pinned to the
dead socket from your first connection (git: `Permission denied (publickey)`,
with Secretive never prompting).

Re-running `outpost dash` also **reconciles windows**: a project you `outpost setup`'d
*after* first opening the dash gets a window added on the next launch (it's added
in the background, so you stay on the window you were viewing). And because the
dash no longer forces window 1 on attach, re-opening it drops you back on the
**last project you were looking at**, not the first one.

## Getting an image into a remote session (`outpost cp`)

Pasting an image with `Ctrl+V` into a remote Claude Code/Codex session does NOT
work: that paste reads the *container's* clipboard, not your Mac's, and no
terminal/SSH protocol carries image bytes across (the dash's OSC52 relay is
text-only). A file PATH always works, so copy the image into the workspace and
reference it:

```bash
outpost cp web ~/Desktop/shot.png    # -> /workspace/shot.png in the container
#   then, inside the project's Claude Code: /workspace/shot.png
```

`outpost cp` uses `docker cp` (works even on a stopped container, no agent needed) and
the host's uid-1000 convention means the file lands owned by the container's
`ubuntu` user. Globs work (`outpost cp web *.png`) since the shell expands them first.

To copy the other way — pull a build artifact **out** of the box — prefix the source with
`:` to mark it as a container path; the last argument is then the host destination:

```bash
outpost cp web :/workspace/dist/app.tar.gz ./   # /workspace/dist/app.tar.gz -> the host CWD
```

With no `:`-prefixed argument, `cp` copies host → `/workspace` as above.
