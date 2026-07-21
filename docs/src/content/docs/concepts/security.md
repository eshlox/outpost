---
title: Security model
description: The threat model and the AI-can-use-my-key problem.
---


## What you are defending against

A malicious npm/pip dependency (or a prompt-injected YOLO agent) that runs during
install/build/test/dev and tries to: read secrets (`~/.ssh`, cloud creds,
tokens), exfiltrate them, pivot to your other projects, or destroy files. The
2025 npm worms (Shai-Hulud) did exactly this, and the nx attack specifically
drove `claude --dangerously-skip-permissions` / `codex` agents to hunt for
secrets - so an always-YOLO setup is a direct target.

## What this design protects

- **Your laptop is untouched.** All dependency execution and all agents run on the
  remote host, never on your laptop. An infected dep never sees your laptop's home,
  Keychain, iCloud, browser, or local keys.
- **Projects are isolated from each other.** One container per project, separate
  filesystem/process namespace and separate `code`/`home` volumes, and **each
  container is on its own per-project Docker network** (`outpost-<project>-net`) - not
  the shared default bridge - so project A cannot even reach project B's services
  by IP. A poisoned install in A cannot read B's source, tokens, home, or sockets.
- **No host secrets in containers.** outpost never mounts your `~/.ssh`, host project
  dirs, or the Docker socket into a container. Only the read-only agent-socket
  directory is reachable, gated by per-use Touch ID.
- **No public exposure.** Published ports bind to `127.0.0.1` on the host;
  inbound is Tailscale-only via your firewall. Containers run
  `no-new-privileges` and as non-root `ubuntu`.
- **Disposable blast radius.** `outpost update` recreates the container from a clean
  base (drops anything that hooked the runtime) and keeps your code + state. `outpost
  destroy` wipes a project entirely.

## Running agents full-auto (YOLO) inside the outpost

A core reason outpost exists: the **container is the security boundary**, not the
agent's permission prompt — so you *can* let agents run without an approval on
every step. The shipped configs are **safe by default** (approval-on); turning on
full-auto is a one-time, documented opt-in — see
[Running agents autonomously](/guides/agents/) for the exact settings.

When you do enable it, an agent can do anything it likes - but only to that one
project's container and volumes, which are isolated from your laptop, your keys,
and every other project, and are disposable. That is the trade: stop babysitting
permission prompts, and contain the blast radius in the layer that actually holds
(the container) instead of the layer that does not (a YES/NO prompt a compromised
dep can talk a model into). Genuinely untrusted code still belongs in a throwaway
VM, not here.

## The honest limits (read these)

- **The host shares one Docker daemon, and your user is in the `docker` group,
  which is root-equivalent on that host.** This design isolates projects from each
  other and protects your laptop; it does not defend the host from the `ubuntu`
  account itself. Genuinely hostile code that you must fully contain from the host
  belongs in its own throwaway VM, not just a container here.
- **Shared kernel between containers.** A kernel-level container escape from one
  project could reach another on the same host. No in-the-wild npm/pip supply-
  chain sample has used a kernel exploit, so for this exfiltration threat the
  no-host-secrets + isolated-volumes boundary is what matters; but know the
  ceiling.
- **Egress is open by default.** A boundary that has no host secrets still holds
  the project's own `.env` and any token you put in it, and can POST to the
  internet (including to an allowed host like github.com). Treat the outpost as able
  to leak whatever you deliberately put inside it.
- **Agent + your identity.** Forwarding your agent is safe against silent abuse only
  with per-use consent (Touch ID, `ssh-add -c`, or a FIDO2 tap) on a **dedicated,
  scoped key** — not your everything-key. That is the threat-model reason for the
  dedicated key; the mechanism is in [Git & SSH](/guides/git-and-ssh/). Genuinely
  untrusted code belongs in a separate throwaway VM, not here.
- **Cloudflare tunnel login leaves an account-wide credential in the box.** If you
  use tunnels, `just tunnel-setup` runs `cloudflared tunnel login`, writing
  `~/.cloudflared/cert.pem` into the project's home volume - a credential that can
  create/delete tunnels and DNS records across your whole Cloudflare zone, sitting
  *inside* the boundary a full-auto agent runs in. Serving a tunnel (`just tunnel`)
  needs only the per-tunnel `<uuid>.json`, so remove `cert.pem` once your routes are
  set (the recipe reminds you), or use an API token scoped to the one zone.
- **A project's host-side config is readable inside the box.** outpost mounts the
  project dir (its `Dockerfile`, `compose.yaml`, `tunnels.json`) read-only at
  `/run/outpost` so the tunnel recipes can read `tunnels.json`. If you put real
  credentials in `compose.yaml` (e.g. a hardcoded `POSTGRES_PASSWORD`), the workspace
  can read them. Keep real secrets out of the project dir; use dev-only values.
- **A project's Dockerfile is trusted.** It runs at `docker build` time as part of
  building the project image, so treat it like host code: a project is only a
  Dockerfile, and an untrusted contributor who could edit one could run build-time
  commands. The orchestrator repo is private and never mounted into a container, so
  an in-container agent cannot reach or change it; keep it that way.

## Layers to add (cheap, high-leverage)

These reduce how often the boundary is the only thing saving you. Bake them into
the base image / your dotfiles so they apply everywhere:

1. **Kill install scripts.** Prefer `pnpm`: it blocks dependency lifecycle
   scripts by default (allowlist the few native builds with `onlyBuiltDependencies`
   on pnpm 10, or `allowBuilds` in `pnpm-workspace.yaml` on pnpm 11). For npm,
   `npm config set ignore-scripts true` today; npm v12 (mid-2026) blocks install
   scripts by default with an `approve-scripts` allowlist, so prefer upgrading npm
   over the manual flag. Caveat: `ignore-scripts` alone is not a wall - a
   malicious git dependency has bypassed it (CVE-2025-69264) by shipping a crafted
   `.npmrc`. So this reduces, not removes, the need for the container boundary.
2. **Dependency cooldown.** A minimum-release-age gate so you are never first to
   install a freshly poisoned version (they are usually pulled within hours).
   pnpm 11 turns `minimumReleaseAge` ON by default at 1440 minutes (1 day); raise
   it to a few days if you like (the unit is minutes). npm/yarn/bun have
   equivalents.
3. **Commit lockfiles, install with `--frozen-lockfile` / `npm ci`.**
4. **Scope credentials per project.** Deploy key or fine-grained, short-lived,
   single-repo token. Never a broad token in a container.
5. **Watch egress.** Optionally run an outbound allowlist proxy in the outpost; at
   minimum, do not place broad tokens inside it. On the Mac, LuLu/Little Snitch
   in alert mode teaches you normal egress.
6. **Container hardening (on by default, no exceptions).** outpost runs every project
   container with `no-new-privileges`, `cap_drop: ALL` (no Linux capabilities),
   its own per-project network, and a generous `--pids-limit` (fork-bomb guard).
   The container never gets the host Docker socket: a project's own services
   (Postgres/Redis/...) run on the HOST engine via `outpost up` and are reached over
   the per-project network, so the workspace has no path to the daemon. Because
   those services run on the host root daemon, `outpost up` lints the compose and
   refuses host-escalating settings (privileged, host namespaces, socket/host-path
   mounts, dangerous caps); override only with `OUTPOST_ALLOW_UNSAFE_COMPOSE=1`. See
   [Services](/guides/services/). Opt into `--memory`/`--cpus` per outpost with
   `OUTPOST_MEMORY` / `OUTPOST_CPUS`, and — for extra containment — a **read-only
   rootfs** with `OUTPOST_READONLY=1` (`--read-only --tmpfs /tmp --tmpfs /run`): the
   container's own filesystem becomes non-persistent, so nothing malware writes outside
   the named volumes survives a restart. Your `code`/`home` volumes stay writable. Opt-in,
   so nothing breaks by default.
7. **Tool downloads.** The base image installs CLI tools from pinned GitHub
   release tarballs over HTTPS (`curl | tar`). TLS protects the download; the pin
   makes it reproducible. There is no checksum step because the only hash a
   publisher offers comes from the same release, so it cannot attest provenance (a
   compromised release matches its own hash) - for that you would pin an
   out-of-band hash you verified yourself. The `curl | sh` installers (fnm/uv)
   are likewise unpinned.
8. **Preflight.** `outpost doctor` checks docker, the Compose plugin, socat, the
   forwarded agent, uid 1000, executable bits, and whether Docker's backing store
   is on a `nosuid` mount (which silently breaks setuid/file-caps in containers).

## Recovery

Your code is in git (pushed). Your container is disposable. To recover from "I
think something is off": `outpost update <project>` (clean runtime, keep code) or
`outpost destroy <project> && outpost setup <project>` (clean everything, re-clone).
Rotate the outpost's scoped key/token if you suspect the outpost itself was reached.
Keep FileVault + encrypted backups on the Mac as the last line.
