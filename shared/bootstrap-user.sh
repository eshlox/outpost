#!/usr/bin/env bash
# Runs INSIDE the container as `ubuntu`, on `outpost setup` and every `outpost update`.
# Must be idempotent. Sets up USER-level state in the persistent /home/ubuntu volume:
#   - applies the default dotfiles baked at /etc/outpost-skel (no chezmoi)
#   - node (via fnm)
#   - Claude Code + Codex + opencode + hunk (npm globals under ~/.npm-global)
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$HOME/.npm-global/bin:$PATH"
warn() { echo "outpost-bootstrap-user: WARNING: $*" >&2; }

# --- dotfiles (default skeleton) ---------------------------------------------
# The repo is the source of truth, so copy (and overwrite) the skeleton on every
# run. Only files present IN the skeleton are touched, so secrets/state outside it
# survive: shell history, ~/.ssh, ~/.claude/.credentials.json, ~/.codex/auth.json,
# and ~/.local/share. NOTE: the skeleton DOES ship ~/.claude/settings.json,
# ~/.codex/config.toml, and ~/.config/opencode/opencode.json (the agent configs -
# safe-by-default in the OSS skeleton), so those are overwritten on every run. That
# means a full-auto opt-in edited directly in the home volume is REVERTED to safe
# defaults on the next `outpost update`; bake it into OUTPOST_DOTFILES_DIR to make it
# durable (see docs/guides/agents.md). Auth, which lives in different files (incl.
# opencode's ~/.local/share/opencode/auth.json), is left untouched.
if [ -d /etc/outpost-skel ]; then
  # --remove-destination replaces each file (and any destination SYMLINK) instead
  # of writing through it. Note: this does not delete dotfiles you remove from the
  # skeleton later - prune those by hand, or `outpost destroy` + setup for a clean home.
  cp -rf --remove-destination /etc/outpost-skel/. "$HOME/"
  # Build the bat theme cache so delta's "Catppuccin Latte" syntax-theme resolves.
  command -v bat >/dev/null 2>&1 && bat cache --build >/dev/null 2>&1 || true
fi

# --- node via fnm -------------------------------------------------------------
if ! command -v fnm >/dev/null 2>&1; then
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --shell bash)"

# Resolve node version explicitly (fnm install does not activate it).
if   [ -f /workspace/.node-version ]; then NODE_VER="$(cat /workspace/.node-version)"
elif [ -f /workspace/.nvmrc ];        then NODE_VER="$(cat /workspace/.nvmrc)"
else NODE_VER=""; fi

if [ -n "$NODE_VER" ]; then
  fnm install "$NODE_VER"
  fnm use "$NODE_VER"; fnm default "$NODE_VER"
else
  # outpost does not clone, so /workspace is empty at first setup - no version to pin.
  fnm install --lts
  fnm use lts-latest 2>/dev/null || true
  fnm default lts-latest 2>/dev/null || true
  echo "outpost-bootstrap-user: no .node-version/.nvmrc in /workspace yet; installed LTS." >&2
  echo "outpost-bootstrap-user: after you clone, run 'fnm install && fnm use' for the project's Node." >&2
fi

npm config set prefix "$HOME/.npm-global"

# --- package manager + AI CLIs (state persists in the home volume) ------------
# corepack was unbundled from Node (gone in v25+), so install pnpm as a normal
# npm global into ~/.npm-global (always on PATH, image ENV + .bashrc) - it resolves
# no matter which Node version fnm activates. pnpm 10 self-manages versions from
# package.json's "packageManager" field, so per-project pinning still holds.
command -v pnpm   >/dev/null 2>&1 || npm install -g pnpm                     || warn "pnpm install failed"
command -v claude   >/dev/null 2>&1 || npm install -g @anthropic-ai/claude-code || warn "claude install failed"
command -v codex    >/dev/null 2>&1 || npm install -g @openai/codex             || warn "codex install failed"
command -v opencode >/dev/null 2>&1 || npm install -g opencode-ai               || warn "opencode install failed"
command -v hunk     >/dev/null 2>&1 || npm install -g hunkdiff                  || warn "hunk install failed"

# --- agent skills (opt-in per preset) -----------------------------------------
# A preset opts in by baking /etc/outpost/skills.list (a SYSTEM path, so it isn't
# masked by the home volume) with one "owner/repo" per line. We install each set
# ONCE, globally, for ALL the agents this box ships - claude-code (~/.claude/skills),
# opencode (~/.config/opencode/skills), codex (~/.codex/skills) - via the official
# `skills` CLI (vercel-labs/skills). Global (not project .agents/skills) because
# outpost starts an EMPTY /workspace with no project dir to scope to; those dirs all
# live in the home volume, so they persist. A sentinel under ~/.local/state keeps
# `outpost update` from re-fetching. Updates stay the user's call:  npx skills update -g
# The skills CLI (vercel-labs/skills) is pinned to a known version so `npx` can't be steered
# to whatever a name-squatter later publishes for the bare `skills` package. Bump deliberately.
SKILLS_CLI="skills@1.5.19"
if [ -f /etc/outpost/skills.list ] && command -v npx >/dev/null 2>&1; then
  skills_state="$HOME/.local/state/outpost/skills"; mkdir -p "$skills_state"
  while read -r repo || [ -n "$repo" ]; do
    case "$repo" in ''|\#*) continue ;; esac
    sentinel="$skills_state/$(printf '%s' "$repo" | tr '/' '_')"
    [ -e "$sentinel" ] && continue
    if npx --yes "$SKILLS_CLI" add "$repo" --skill '*' \
         -a claude-code -a opencode -a codex --global --yes; then
      : >"$sentinel"
    else
      warn "skills add $repo failed (offline?); will retry next update, or run 'npx skills update -g'"
    fi
  done < /etc/outpost/skills.list
fi

echo "outpost-bootstrap-user: done"
