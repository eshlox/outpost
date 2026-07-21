---
title: Git & SSH
description: Forwarded-agent git signing, gated by your laptop.
---


You use one Secretive (Secure Enclave) key for both git auth and commit signing.
The question is how it reaches a container without becoming a free pass for a
YOLO agent or an infected dependency running in that container.

The approach: forward the Secretive agent, gated by Touch ID.

`outpost` runs a per-project `socat` bridge that re-points a stable in-container
socket (`/run/agent/agent.sock`, mounted read-only) at your forwarded
`$SSH_AUTH_SOCK`. So git inside the container authenticates (and, once you turn on
signing, signs) through your Mac's Secure Enclave. The private key never leaves
the enclave and is never copied to your host or any container.

Commit signing is **opt-in**. The repo ships
`shared/home/.config/git/local.gitconfig.example` with the `[gpg]`/`[commit]`/`[tag]`
blocks commented out; to enable signing, copy it to `local.gitconfig` (which
`.gitconfig` already `[include]`s), fill in your name/email and your Secretive PUBLIC
key in `signingkey` (a public key, fine to commit to your private configs repo), and
uncomment those blocks plus `~/.ssh/allowed_signers` for local verification. Once on,
every commit/tag is signed via the same forwarded agent, Touch-ID gated like
everything else - so each signature triggers a per-use Touch ID prompt and the private
key never leaves the Mac's Secure Enclave. For the "Verified" badge on GitHub, add the
same public key under Settings -> SSH and GPG keys -> *Signing keys* (a separate upload
from your authentication key).

The key fact for the AI problem: create the Secretive key with
**authentication required (Touch ID / Apple Watch), not the "Notify" option**.
Secretive has no caching or timeout setting (there is nothing to "set to 0"); an
auth-required key simply re-prompts on every use, and Secretive's FAQ confirms a
remote/forwarded use must be authenticated through Secretive too. So every git
push / fetch / signed commit from inside the container - including one an agent or
a malicious dependency tries to run - triggers a **Touch ID prompt on your Mac**.
The agent cannot use your identity autonomously; it has to ask, and you see and
approve each use. A blank check becomes per-use consent. (Do not pick "Notify":
it only notifies, it does not block the use.)

What this gives and does not give:

- Cannot be stolen: the key is non-extractable hardware; forwarding lends its
  USE, not its bytes.
- Cannot be used silently: with per-use Touch ID, no push or signature happens
  without your fingerprint.
- Still your full identity WHILE you approve: if you approve a prompt, you cannot
  tell whether it was your `git push` or the agent's. So this protects against
  silent/background abuse, not against you rubber-stamping a prompt the agent
  triggered at the same moment you expected your own.

Operational rules:

- Use a **dedicated key** for this outpost, registered on GitHub with only the
  access you need — not your one personal everything-key. (This is the mechanism;
  the [security model](/concepts/security/) covers *why* — the threat model.)
- Keep the key as auth-required; do not switch it to "Notify" and do not enable
  any future caching/timeout feature.
- The bridge only exists while you have an `ssh -A` session and ran `outpost sh`. If
  you are not actively in the outpost, there is no live agent for an agent to abuse.

The read-only mount is not the gate. outpost bind-mounts the agent-socket directory
read-only so the container cannot delete or replace the socket or touch the
host-side bridge state (and so a socat restart is transparent). It does NOT stop
the container from connecting to the socket and using the agent - that is what
the per-use Touch ID gate is for.

A uid coupling to know: the bridge socket is created mode 0600 owned by your host
user, and the container's `ubuntu` user is uid 1000. Forwarding therefore assumes
your host login user is also uid 1000 (the first Ubuntu user is). If it is
not, outpost warns, and git inside the outpost may fail to read the agent; run outpost as a
uid-1000 user. Do not "fix" it by loosening the socket mode - that would expose
the forwarded agent to other users on the host.

For a genuinely untrusted project, the right move is not a clever key setup - it
is a separate disposable VM, not a container on this shared-kernel outpost.

## Not on macOS? (per-use consent without Secretive)

Secretive + Touch ID is the showcase, but nothing here is macOS-specific — outpost
runs entirely on the Linux host and just needs a forwarded agent. The property that
matters is **per-use consent on the client**, and every platform has an analog:

- **Linux / any OpenSSH agent** — add the key with `ssh-add -c` (confirm-per-use). The
  agent then prompts (via `ssh-askpass`) for confirmation on **every** signature, so a
  forwarded use inside the box pops a dialog on your machine, exactly like Touch ID.
- **FIDO2 hardware keys** — generate an `-sk` key (`ssh-keygen -t ed25519-sk`, or
  `ecdsa-sk`) and add the `verify-required`/touch options. Each git operation then
  requires a physical tap on the security key (a YubiKey, etc.) — hardware-backed per-use
  consent that works on Linux and Windows too.
- **Windows** — use a FIDO2 `-sk` key as above, or a forwarded agent with a confirm
  step; the point is the same: the key's *use* must require an interactive tap.

Whatever the client, the outpost side is identical: the private key never enters the
container, and the agent bridge only relays a use you consented to.

## Extra hardening

- Never bind-mount your `~/.ssh` into the host or a container; never mount the Docker
  socket into a container. outpost does neither.
- See the [security model](/concepts/security/) for the full picture, including egress
  and dependency hygiene that reduce how often the key is the only thing standing in the
  way, and the threat-model rationale for the dedicated, scoped key.
