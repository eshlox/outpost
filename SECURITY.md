# Security Policy

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue for a
vulnerability. Use GitHub's [private vulnerability reporting](https://github.com/eshlox/outpost/security/advisories/new)
(the **Security → Report a vulnerability** button on the repo). You'll get an acknowledgement
and a fix or mitigation timeline.

## Scope & threat model

outpost runs untrusted code (dependencies, AI agents) inside per-project containers on a
host you control. The design assumes the **workspace is hostile** and aims to keep it
contained. Key properties:

- Containers run with `--cap-drop ALL`, `--security-opt no-new-privileges`, on a per-project
  bridge network, with a `--pids-limit` fork-bomb guard and **no host Docker socket** and no
  added devices.
- A project's services run on the host engine via `outpost up`; their `compose.yaml` is
  **linted to refuse host-escalating settings** (privileged, host namespaces, dangerous
  caps, seccomp/apparmor unconfined) unless you explicitly set `OUTPOST_ALLOW_UNSAFE_COMPOSE=1`.
  Host-path exposure is checked by **allowlist**: every bind `source:`, secret/config
  `file:`, driver_opts `device:`, and build `context:` is `realpath`-resolved (so a
  project-local symlink or `../` escape can't slip through) and refused unless it lands
  inside the project directory.
- Git uses your **forwarded** SSH agent (`ssh -A`); the private key never enters the
  container. On macOS the key can live in Secretive's Secure Enclave, Touch-ID gated.

The deeper rationale ("the AI can use my key" problem, the agent bridge, the isolation
boundary) is documented in the [security model](https://outpost.eshlox.net/concepts/security/).

## Trust & supply chain (intentional tradeoffs)

These are deliberate choices, not oversights — know them before you rely on outpost:

- **Tool fetches trust TLS, not pinned checksums.** The base image and bootstrap download
  release tarballs and vendor installers (`fnm`, `uv`) over HTTPS and run them; integrity
  rests on TLS + the source (GitHub/vendor), not a separately published checksum or
  signature (a same-origin checksum adds no provenance). Tool *versions* are pinned as
  Dockerfile `ARG`s where it matters and are easy to audit/bump.
- **The AI CLIs track upstream.** `claude` / `codex` / `opencode` install as latest into
  the per-project home volume **on purpose**, so they self-update; they are not version
  pinned. Agent skills likewise come from their upstream repos via `npx skills`.
- **`OUTPOST_CONFIG` is executed as shell.** Your config file is `source`d by `outpost`, so
  treat it like your shell rc: keep it under your control and never point `OUTPOST_CONFIG`
  (or `XDG_CONFIG_HOME`) at untrusted content — it runs with your privileges.

If your threat model needs pinned/verified supply chains, fork the base `Dockerfile` and
`bootstrap-user.sh` to pin exact versions and verify signatures.

## What is *not* in scope

- The security of code/agents you run inside the workspace — that's exactly what the
  container boundary is for; assume it can do anything a normal process can within the
  container.
- Misconfigurations that disable the protections above (e.g. `OUTPOST_ALLOW_UNSAFE_COMPOSE`).
- The host itself (OS hardening, firewall, SSH config) — see
  [Host provisioning](https://outpost.eshlox.net/guides/host-provisioning/).
