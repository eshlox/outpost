---
title: Running agents autonomously
description: Why the box makes "YOLO" agent mode reasonable, and how to opt in.
---

A big reason outpost exists is to give AI coding agents (Claude Code, Codex, opencode) a
place where they can run **without an approval prompt on every step** — *safely*, because
the container is a hardened, disposable sandbox, not your laptop.

Claude (`defaultMode: default`) and Codex (`approval_policy = "untrusted"`) ship
**approval-first** — they ask before acting. opencode is the exception: its shipped
`opencode.json` is just a `$schema` line with **no `permission` block**, so it runs
opencode's own built-in defaults; add a `permission` block if you want to pin its behaviour
either way. Autonomy is an explicit opt-in, so you never hand a stranger's machine full
auto-approve on first run. On **your** machine, turning it on is a one-time edit.

## Why it's reasonable here

The workspace container runs with `--cap-drop ALL`, `no-new-privileges`, on a per-project
network, with no host Docker socket and a fork-bomb guard (see the
[security model](/concepts/security/)). The blast radius of a misbehaving agent is that
project's container and its two volumes — which `outpost destroy` wipes. Git still goes
through your forwarded agent, so even an autonomous agent can't exfiltrate your signing key.

That said: an autonomous agent **can** do anything to the code in `/workspace` and reach the
network. Keep secrets out of the workspace, and rely on the container boundary — not the
agent's good behaviour.

## Turn it on

Bake the change into your own dotfiles via `OUTPOST_DOTFILES_DIR` (`outpost base` then
`outpost update`). You *can* also just edit the configs in the container's home volume —
but note that `outpost-bootstrap-user` re-applies the shipped skeleton on **every
`outpost update`**, so a home-volume edit is reverted to the safe default the next time
you update. That revert is deliberate (safe-by-default reasserts itself); `OUTPOST_DOTFILES_DIR`
is the durable opt-in.

**Claude Code** — `~/.claude/settings.json`:

```json
{
  "permissions": { "defaultMode": "bypassPermissions" },
  "theme": "auto"
}
```

**Codex** — `~/.codex/config.toml` (the persistent equivalent of `codex --yolo`):

```toml
approval_policy = "never"
sandbox_mode    = "danger-full-access"

[projects."/workspace"]
trust_level = "trusted"
```

**opencode** — `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": "allow"
}
```

The opencode `permission` field accepts a bare string (`"ask"` / `"allow"` / `"deny"`) as
above, or an object for per-tool control (e.g. `{ "bash": "ask", "edit": "allow" }`).

To turn it **off** again, restore the shipped defaults — see
`shared/home/.claude/settings.json` (`defaultMode: default`), `.codex/config.toml`
(`approval_policy = "untrusted"`), and `.config/opencode/opencode.json` (just the `$schema`
line — drop the `permission` block) in the repo.
