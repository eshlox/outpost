---
title: Troubleshooting & FAQ
description: The diagnosable failure modes — symptom, cause, and fix — cross-referenced to the code.
---

Most outpost failures are one of a small set of preflightable conditions. Run
`outpost doctor` first (it checks the engine, socat, the forwarded agent, uid 1000,
executable bits, the base image, the Compose plugin, and the `nosuid` backing store).
Below, each message is matched to its cause and fix.

## `no image for <project> yet (run: outpost setup <project>)`

- **Symptom.** `outpost sh`/`start`/`ports` on a project that has never been built.
- **Cause.** The project image `outpost-<project>:latest` doesn't exist. outpost fails
  fast here on purpose — otherwise `docker run` would try to *pull* the name from a
  registry and hang on a confusing "pull access denied".
- **Fix.** `outpost setup <project>` (builds the base if missing, builds the project image,
  starts the container, bootstraps). Thereafter `outpost update <project>` rebuilds it.

## `base image not built yet (run: outpost base)`

- **Symptom.** `outpost doctor` warns; a first `outpost setup` spends ~minutes building.
- **Cause.** `outpost-base:latest` hasn't been built yet. `setup` builds it automatically;
  the warning just tells you the first run will be slow.
- **Fix.** `outpost base` to build it ahead of time.

## `refusing to use <STATE_DIR> (exists but not owned by you)`

- **Symptom.** Any project command dies immediately.
- **Cause.** The host-only state dir (default `$XDG_RUNTIME_DIR/outpost`, else
  `/tmp/outpost-<uid>`) already exists but is owned by another user. Because the `/tmp`
  fallback path is predictable and world-writable, outpost refuses it rather than risk a
  local user having pre-created it to read your forwarded agent.
- **Fix.** Remove or chown the offending dir (`rm -rf /tmp/outpost-$(id -u)` if it's stale
  and yours to remove), or point `OUTPOST_STATE_DIR` at a private dir you own. Never make it
  group/other-writable.

## `agent bridge did not start: <socket>`

- **Symptom.** `outpost sh`/`update`/`dash` dies right after "starting" the bridge.
- **Cause.** The `socat` listener didn't create the socket in time. The common real-world
  trigger is a **root-owned agent dir**: if a `--no-agent` run (or a crash) left
  `$STATE_DIR/agents/<project>/run` owned by root, `socat` can't bind a socket there.
- **Fix.** Remove the project's agent state and retry: `rm -rf "$STATE_DIR/agents/<project>"`
  (use `sudo` only if it's root-owned), then `outpost sh <project>`. Confirm `socat` is
  installed (`outpost doctor`).

## `no SSH agent forwarded` / `SSH_AUTH_SOCK is not a socket`

- **Symptom.** Bridge setup dies before attaching.
- **Cause.** You connected without agent forwarding, so there's no `$SSH_AUTH_SOCK` to relay
  into the container.
- **Fix.** Reconnect with `ssh -A dev-box`. For a client that has no agent to forward (e.g.
  Termius on iOS), attach observe-only with `outpost sh <project> --no-agent` (git
  push/signing won't work in that session).

## Git dies after a reconnect (`Permission denied (publickey)`, Secretive never prompts)

- **Symptom.** Git worked, you closed the laptop / dropped the link, reconnected, and now
  git inside a long-lived tmux/`dash` fails — and Secretive never even asks for Touch ID.
- **Cause.** The old forwarded `$SSH_AUTH_SOCK` died with the old SSH session; the bridge is
  still pointed at the dead socket.
- **Fix.** Re-run `outpost sh <project>` (or `outpost dash`) — both re-point the stable
  in-container socket at your **new** forwarded agent. Don't `tmux attach` the dash by hand;
  that skips the re-point. This is the daily-loop self-heal, not a bug.

## `host uid <n> != 1000` (git can't read the forwarded agent)

- **Symptom.** `outpost doctor` warns; git inside the box fails to reach the agent.
- **Cause.** The forwarded agent socket is mode 0600 owned by your host user, and the
  container's `ubuntu` user is uid 1000 — so the host login user must also be uid 1000 to
  read it.
- **Fix.** Run outpost as a uid-1000 user: make one the login user (the first Ubuntu user is
  uid 1000) or `sudo -u <uid-1000-user> -i` before using outpost. Do **not** loosen the
  socket mode — that would expose the forwarded agent to other users on the host.

## `sudo` / `ping` mysteriously broken inside the container (nosuid backing store)

- **Symptom.** setuid binaries and file capabilities silently stop working *inside*
  containers, with no obvious cause. `outpost doctor` warns:
  `<path> is on a nosuid mount (setuid/file-caps break inside containers)`.
- **Cause.** Docker's backing store (`DockerRootDir`, `/var/lib/docker`, or
  `/var/lib/containerd`) sits on a mount with the `nosuid` option, which drops setuid/file
  caps at `exec`.
- **Fix.** Move Docker's data-root to a mount **without** `nosuid`, or remount that
  filesystem without the option. This is a host mount-config issue, not an outpost bug.

## A pinned port fails to publish (`docker run` errors loudly)

- **Symptom.** `outpost setup`/`update` fails at container-run time with a port-in-use error.
- **Cause.** A `ports.pin` entry pins a fixed host port that another running project already
  pinned to the same number. Unlike the default dynamic ports, pinned ports **can** collide
  — outpost lets `docker run` fail loudly rather than silently pick another.
- **Fix.** Change the number in one project's `ports.pin`, or drop the pin to fall back to a
  dynamic, collision-free host port. Only pin the ports you truly need stable for a
  long-lived `ssh -L`.

## `container for <project> is not running`

- **Symptom.** `outpost exec <project> …` refuses to run.
- **Cause.** `exec` needs a running container (it's for scripting/CI, no tmux).
- **Fix.** `outpost start <project>` (or `outpost sh <project>`) first.

## `<project> still has a container; run 'outpost projects rm <project> --destroy'`

- **Symptom.** `outpost projects rm` refuses.
- **Cause.** Removing the config dir would orphan a container outpost could no longer
  stop/destroy.
- **Fix.** `outpost destroy <project>` first (drops the container + volumes), then
  `outpost projects rm <project>` — or do both at once with `--destroy`.

## `refusing to start <project> services — its compose requests host-escalating settings`

- **Symptom.** `outpost up` refuses to start a project's services.
- **Cause.** The compose lint (fail-closed) found a host-escalating setting — `privileged`,
  a host/container namespace join, `volumes_from`, a published host port, a dangerous
  `cap_add`, a `security_opt` relaxation, or a bind/secret/context path escaping the project
  dir. These run on the host root daemon and would breach the workspace isolation.
- **Fix.** Remove the flagged setting (reach services by name on the project network instead
  of publishing ports). Only if you fully accept the risk, re-run with
  `OUTPOST_ALLOW_UNSAFE_COMPOSE=1`. See the [security model](/concepts/security/) and
  [internals](/reference/internals/#compose-lint-host-escalation-refusal).

## FAQ

- **Can I install packages inside a running container?** Ad-hoc root installs mostly don't
  work by design (`--cap-drop ALL` breaks dpkg's chown), and anything you *do* install is
  lost on the next `outpost update`. Put system tools in the project's `Dockerfile` (or
  `shared/Dockerfile` for the base) and rebuild — that's the package manager.
- **Where does my data live?** In two named volumes per project: `outpost-<p>-code`
  (`/workspace`) and `outpost-<p>-home` (`/home/ubuntu`). They survive container recreation
  and `outpost update`. See [Backups & migration](/guides/backups/).
- **My host isn't uid 1000 and I can't change it.** See the uid section above and the
  uid caveat in [Is this for you?](/is-this-for-you/).
