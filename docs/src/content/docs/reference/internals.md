---
title: Internals — why the code looks like this
description: The load-bearing engineering rationale behind bin/outpost, kept out of the script so the code stays skimmable.
---

`bin/outpost` is a single, plain-`bash` script you can read top to bottom. To keep it
skimmable, the *deep* "why is this line written this odd way" rationale lives here
instead of in long comment blocks. Each section is anchored so a one-line pointer in the
code (`# ... see docs/reference/internals#<anchor>`) can bring you straight here.

This is a maintainer's document. If you just want to *use* outpost, you never need it.

## Project name validation

`valid_name` restricts a project name to `^[a-z0-9]([a-z0-9_-]{0,61}[a-z0-9])?$`. The
name is not cosmetic: it flows into filesystem paths, the container/volume/network names,
**and** the image tag `outpost-<name>:latest`. Docker image references must be lowercase,
so an uppercase name would fail the build. The name must also **end** alphanumeric — a
trailing `-`/`_` (e.g. `demo-`) produces `outpost-demo-:latest`, an invalid tag the engine
rejects. 63 chars max keeps every derived identifier within Docker's limits. The same
check gates every path the tool builds from a name, including the `rm -rf` in
`projects rm`, so `../foo`-style traversal never reaches the filesystem.

## State dir and the agent-bridge socket

`STATE_DIR` holds the host-only state for the SSH-agent bridge (see below). Two
constraints shape it:

- **Socket path length.** A unix-domain socket path must stay under ~108 bytes. The bridge
  socket lives at `$STATE_DIR/agents/<project>/run/agent.sock`, so `STATE_DIR` must be
  *short* — rooting it at a long `$HOME/<...>/project` path would blow the limit for
  long project names.
- **Not age-cleaned.** We prefer `$XDG_RUNTIME_DIR` (a per-user tmpfs at mode 0700) over
  `/tmp`, because `systemd-tmpfiles` age-cleans `/tmp` and would delete the bridge socket's
  bind-mount source out from under a long-lived container — silently breaking git in a box
  that has been running for days. When `$XDG_RUNTIME_DIR` is unset (headless/cron logins),
  we fall back to a private `/tmp/outpost-<uid>` dir.

Because that fallback path is predictable and sits in world-writable `/tmp`, `load_project`
creates it with `umask 077` and then **refuses a pre-existing dir owned by anyone else**.
Otherwise a local attacker could pre-create `/tmp/outpost-<uid>` and read your forwarded
agent. Override the whole thing with `OUTPOST_STATE_DIR`.

## The SSH-agent bridge

Git inside the container uses your **forwarded** SSH agent (`ssh -A`). The problem: each
SSH connection hands out a *new* `$SSH_AUTH_SOCK` and the old one dies with the
connection, but the container is long-lived. So we don't mount `$SSH_AUTH_SOCK` directly.

Instead `ensure_bridge` runs a `socat` that listens on a **stable** per-project socket and
forwards to *this session's* `$SSH_AUTH_SOCK`. The container bind-mounts the socket's
**directory** read-only, so restarting `socat` (pointing it at a fresh agent after a
reconnect) is invisible to the running container — the path never changes.

Details that look odd but matter:

- **"Only kill if it's still our socat."** Before re-pointing, we kill the previous
  `socat` — but only after confirming the recorded PID's `/proc/<pid>/cmdline` still
  references our socket. A bare `kill "$oldpid"` could hit an unrelated process that
  reused the PID.
- **uid 1000.** The forwarded socket is mode 0600 owned by the host user; the container's
  `ubuntu` user is uid 1000, so the host user must also be uid 1000 to read it. We warn
  (not fail) when it isn't — see [Git & SSH](/guides/git-and-ssh/).
- **`OUTPOST_SKIP_BRIDGE`.** Set by `outpost sh --no-agent` (and by the tests, which have
  no live agent). It doesn't merely skip the refresh — it *tears down* any existing bridge
  so the session is genuinely agentless (the socket disappears), rather than leaving a
  stale socket a forwarded agent could still reach.

## Port publishing and `ports.pin`

Ports come from the **built image** (`EXPOSE` in the Dockerfile) — outpost never guesses.
Each is published to `127.0.0.1` on a **dynamic** host port (`-p 127.0.0.1::<port>`, empty
host port = docker picks a free one), so several projects can all `EXPOSE 3000` without
colliding. `outpost ports <project>` prints the assigned host ports with a copy-paste
`ssh -L`.

The dynamic port changes each run, which is annoying for a long-lived `ssh -L` from your
laptop. An optional `ports.pin` file beside the Dockerfile (not in the repo volume) pins a
fixed host port. One port per line, `#` comments and blanks ignored:

```
3333          # publish container 3333 on host 127.0.0.1:3333 (1:1)
4322:14322    # or map container 4322 -> host 14322
```

Unlisted `EXPOSE`d ports keep the dynamic, collision-free host port. Pinned host ports
**can** collide across projects (then `docker run` fails loudly) — that's the trade-off you
opt into for a stable port.

## Container run flags

The hardening (`--security-opt no-new-privileges:true --cap-drop ALL`, per-project
network, `--pids-limit`) and the "no host Docker socket" stance are covered in the
[security model](/concepts/security/). Two run-flag details that live only here:

- **`/run/outpost` bind.** We surface the project's host config dir (its `Dockerfile`,
  `compose.yaml`, `tunnels.json`) read-only at `/run/outpost` so the in-container
  `just tunnel` recipes can read `tunnels.json` — which lives beside the Dockerfile on the
  host, not in the workspace volume. It's a **directory** bind (not a single-file bind) so
  editing `tunnels.json` on the host is reflected live in a long-lived container. Read-only,
  and only the project's own build metadata — no host secrets.
- **No restart policy.** After a host reboot the forwarded agent socket is dead until your
  next `outpost sh` anyway, so auto-restarting the container buys nothing; `outpost sh` /
  `setup` start it when you actually need it.

## `update`: swap-with-rollback and the `set -e` gotcha

`outpost update` rebuilds on a fresh base but must never leave you with *no* working
container. So `_update_project` **renames** the old container to `<name>.bak` and only
removes it once the new one is confirmed up **and** bootstrapped; any failure rolls back to
the renamed original (volumes are untouched throughout).

The non-obvious part is the `|| return 1` on every pre-swap step. The `--all` loop calls
`_update_project "$p" || ...`. When a function's return status is tested like that, bash
**disables `set -e` for the entire function body**. Without the explicit `|| return 1`, a
failed `build_project_image` would not abort — execution would fall through, rename and
swap the old container for one built from the **stale** previous image, and report success.
The explicit returns are what keep the "a failed build keeps the old container" guarantee
true on both the single-project and the `--all` path. Do not "clean them up."

## The `dash` (host tmux project switcher)

`outpost dash` is one **host** tmux that wraps `outpost sh <project>` per window, so a
single SSH/Termius connection can flip between every project's in-container tmux. It runs on
a **dedicated tmux server** (`tmux -L outpost-dash`) with its own socket, so its options
never leak into any other host tmux. It takes prefix `C-a` (the containers keep `C-b`) and
turns its status bar off, so it's an invisible switcher layered under the real tmux.

- **Respawn loop.** Each window runs a `while :; do ... outpost sh ...; done` loop, so
  detaching a project's inner tmux (`C-b d`) snaps right back into it instead of closing the
  window — you leave the dash only with `C-a d`. `outpost stop`/`rm`/`destroy` kill the
  window (and thus the loop) *first*, so the loop can't recreate the box ~0.3 s later.
- **Healing git auth across reconnects.** Every respawn re-reads `$SSH_AUTH_SOCK` from the
  dash server's environment, and every `outpost dash` invocation republishes the current
  session's live socket into that environment and re-points each project's bridge. Without
  this, a long-lived dash would pin the first connection's now-dead socket and git would
  fail with "Permission denied (publickey)" (Secretive never even prompts).
- **Reconcile on re-entry.** If the dash session is still alive from a previous detached
  launch, the create loop is skipped; we instead add a window for any requested project
  that lacks one (else a project you `outpost setup`'d *after* first opening the dash never
  appears). New windows are added in the background (`-d`) so re-attaching lands on the
  window you last viewed, not the freshly added one.
- **Switcher options re-applied every attach.** `prefix C-a` + `status off` keep it from
  clashing with the containers' `C-b` / `Option+N`; `mouse on` + `set-clipboard on` + the
  `clipboard` terminal-feature forward the mouse to the focused project and relay *its*
  OSC52 copy up to your laptop clipboard through the extra tmux layer. Re-applying on every
  attach also means a tool upgrade takes effect on the next `outpost dash`.

## `exec`: reproducing the interactive shell

`outpost exec` runs a one-off command through a **login** shell that re-exports the
interactive `PATH` and re-runs `fnm` activation, because the non-interactive `.bashrc`
returns early — so `node`/`pnpm`/etc. resolve exactly as they do inside `outpost sh`. The
command's argv is passed positionally after `_` (which becomes `$0`) so arguments with
spaces survive intact instead of being re-split. A TTY is allocated only when both stdin
and stdout are TTYs, so interactive REPLs work but CI/cron output isn't mangled by pty
processing.

## Compose lint (host-escalation refusal)

A project's own services run on the **host root daemon** via `outpost up`, so a hostile or
careless `compose.yaml` could punch straight through the workspace isolation. `lint_compose`
renders the **resolved** config (`docker compose config` normalizes short/long forms,
anchors, and env into stable 2-space YAML, so the checks don't depend on how the file is
written) and refuses these, fail-closed (override with `OUTPOST_ALLOW_UNSAFE_COMPOSE=1`):

- **`privileged: true`** — full host access.
- **Namespace joins** (`network_mode`/`pid`/`ipc`/`userns_mode`/`cgroup_parent: host` or
  `container:`/`service:`) — hand a service the namespace of something outside its own
  sandbox, whether the host's or another container's.
- **`volumes_from`** — mounts another container's volumes (its data and any binds it
  carries).
- **Published host ports** (`published:` in the rendered config; container-only `expose:`
  has none) — publishing bypasses UFW (Docker inserts its own DNAT rules ahead of it) and
  is unnecessary here, since services are reachable by name on the project network.
- **Dangerous `cap_add`** (`ALL`, `SYS_ADMIN`, `SYS_MODULE`, `SYS_PTRACE`, `SYS_RAWIO`,
  `DAC_READ_SEARCH`, `BPF`, `MKNOD`). The check is block-scoped with `awk` so it fires only
  under `cap_add`, never the common and *good* `cap_drop: ALL`; a plain token match would
  false-positive on the drop list.
- **`security_opt` relaxations** — `apparmor:unconfined`, `seccomp:unconfined`,
  `no-new-privileges:false`.
- **Host paths escaping the project dir.** A bind `source`, secret/config `file`,
  `driver_opts` `device`, build `context`, or an `additional_contexts` entry (a Dockerfile
  can `COPY` from it) can all read host state past the isolation — the Docker socket,
  `~/.ssh`, `/etc`, anywhere. `docker compose config` resolves each to an **absolute** path,
  so rather than a denylist of "bad" paths we **allowlist**: only paths that resolve inside
  the project dir pass. We canonicalize with `realpath` **first**, so a project-local
  symlink (`$PDIR/seed -> ~/.ssh`) or a `../` escape can't smuggle a host path past the
  prefix check. Non-absolute values (named volumes, tmpfs, `docker-image://` refs) aren't
  paths and fall through untouched. `additional_contexts` uses arbitrary key names, so it
  needs block-scoped extraction rather than a fixed `key:` match.

## doctor: the `nosuid` backing-store check

If Docker's backing store (`DockerRootDir`, `/var/lib/docker`, `/var/lib/containerd`) sits
on a `nosuid` mount, setuid binaries and file capabilities are **silently** dropped at
`exec` *inside* containers — `sudo`, `ping`, etc. stop working with no obvious cause. It
isn't outpost's own failure mode, but it's a cheap, real gotcha to surface, so `doctor`
warns when it finds one (using `findmnt`, itself gated on availability).

## projects repo safety: `git add -A` and nesting

`projects_autocommit` / `projects sync` run `git add -A`, which stages the **whole** repo
tree regardless of cwd. If `OUTPOST_PROJECTS_DIR` happened to sit *inside* an outer git
repo, that would commit and push the outer repo's unrelated files. So `projects_is_git`
returns true **only** when `OUTPOST_PROJECTS_DIR` is the repo's top level, not merely nested
inside one. When it's nested, we report "not a repo" so `outpost projects init` makes the
projects dir its own (nested) repo instead of ever operating on the parent.
