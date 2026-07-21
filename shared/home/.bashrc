# Default shell config for the outpost container (bash).
# outpost starts tmux via `outpost sh`, so there is no multiplexer auto-start here; tool
# inits are guarded so a missing tool never breaks the shell.

# Only run the interactive bits for interactive shells.
case $- in *i*) ;; *) return ;; esac

# (TERM + COLORTERM are pinned in the image so truecolor survives ssh + docker
# exec; see shared/Dockerfile. No shell-side TERM fixup needed.)

# History
HISTFILE="$HOME/.bash_history"
HISTSIZE=1000000
HISTFILESIZE=1000000
HISTCONTROL=ignoreboth      # ignore duplicate + leading-space commands
shopt -s histappend         # append, don't overwrite, on exit

# Flush each command to HISTFILE the instant it runs, not on shell exit. `outpost
# update` stops the container (SIGTERM/KILL), so tmux shells never exit cleanly
# and histappend alone would lose everything typed since the session started.
# Set BEFORE `starship init` below - starship preserves an existing PROMPT_COMMAND.
PROMPT_COMMAND="history -a"

# Completion
[ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion

# Tools - guarded with `command -v` so the shell still loads if one is absent.
command -v fzf      >/dev/null && eval "$(fzf --bash)"               # Ctrl-R/Ctrl-T/Alt-C
command -v starship >/dev/null && eval "$(starship init bash)"      # prompt
command -v fnm      >/dev/null && eval "$(fnm env --use-on-cd --shell bash)"  # per-dir Node
export FZF_DEFAULT_OPTS='--color=light --height=40% --layout=reverse --border'

# Environment
export PATH="$HOME/.local/bin:$PATH"   # personal scripts - PREPEND, never replace
export EDITOR="hx"
export VISUAL="hx"

# NOTE: the upstream dotfiles auto-start a multiplexer; outpost starts tmux for you
# (`outpost sh` attaches a per-project session), so no auto-start here. Inside tmux
# ($TMUX set), new panes just run bash.

# Prepare a project's Mutagen sshd files, but ONLY where the project opted in by
# installing openssh-server (the `outpost-sshd` helper itself ships in every base
# image - see examples/mutagen-sshd). Gating on /usr/sbin/sshd keeps this a no-op in
# projects that don't use Mutagen. `outpost-sshd --ensure` is idempotent + quiet: it
# just makes sure the host key + sshd_config exist so the Mutagen `docker exec ...
# sshd -i` ProxyCommand is ready. See docs/mutagen-sync.md.
[ -x /usr/sbin/sshd ] && command -v outpost-sshd >/dev/null && outpost-sshd --ensure

# `just` wrapper: falls back to the global ~/.config/just/justfile, renames the
# tmux window to the recipe while it runs (inert unless $TMUX set), and `--choose`
# fuzzy-picks project + global recipes. Identical CLI surface to plain `just`.
just() {
  local global_justfile="${XDG_CONFIG_HOME:-$HOME/.config}/just/justfile"

  local in_project=0
  command just --show default &>/dev/null && in_project=1
  if (( ! in_project )); then
    command just --summary &>/dev/null && in_project=1
  fi

  if [[ "$1" == "--choose" ]]; then
    local chooser="${JUST_CHOOSER:-fzf --ansi}"
    local project_list="" global_list="" selected
    if (( in_project )); then
      project_list=$(command just --summary 2>/dev/null | tr ' ' '\n' | grep -v '^$')
    fi
    if [[ -f "$global_justfile" ]]; then
      global_list=$(command just -g --summary 2>/dev/null | tr ' ' '\n' | grep -v '^$')
    fi
    selected=$(
      {
        [[ -n "$project_list" ]] && while IFS= read -r r; do printf '  %s\n' "$r"; done <<< "$project_list"
        while IFS= read -r r; do
          [[ -z "$r" ]] && continue
          if [[ -z "$project_list" ]] || ! echo "$project_list" | grep -qxF "$r"; then
            printf '\033[2m∘\033[0m %s\n' "$r"
          fi
        done <<< "$global_list"
      } | eval "$chooser" | awk '{print $NF}'
    ) || return
    [[ -z "$selected" ]] && return
    just "$selected"
    return
  fi

  local recipe=""
  for arg in "$@"; do
    [[ "$arg" == -* ]] && continue
    recipe="$arg"; break
  done

  if [[ "$1" == "--list" || "$1" == "-l" ]]; then
    if (( in_project )); then command just "$@"; fi
    if [[ -f "$global_justfile" ]] && command just -g --list &>/dev/null; then
      (( in_project )) && echo ""
      echo "Global recipes:"
      command just -g "$@"
    fi
    return
  fi

  if [[ $# -eq 0 ]] && (( ! in_project )) && [[ -f "$global_justfile" ]]; then
    command just -g
    return
  fi

  local -a prefix=(command just)
  if [[ -n "$recipe" ]] \
    && [[ -f "$global_justfile" ]] \
    && ! command just --show "$recipe" &>/dev/null \
    && command just --justfile "$global_justfile" --show "$recipe" &>/dev/null; then
    prefix=(command just --justfile "$global_justfile" --working-directory "$PWD")
  fi

  if [[ -n "$TMUX" ]] && [[ -n "$recipe" ]]; then
    tmux rename-window "$recipe"
    "${prefix[@]}" "$@"; local exit_code=$?
    tmux set-window-option automatic-rename on   # hand the name back to tmux
    return $exit_code
  fi

  "${prefix[@]}" "$@"
}
alias j="just --choose"
