#!/usr/bin/env bash
# Symlink `outpost` onto your PATH on the remote host. Run once after cloning:
#   git clone git@github.com:<you>/outpost.git ~/outpost
#   ~/outpost/install.sh && source ~/.bashrc
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HOME/bin"
ln -sf "$REPO_DIR/bin/outpost" "$HOME/bin/outpost"

# Pick the rc file for the user's LOGIN shell, not the bash running this script
# (under bash, ZSH_VERSION is always unset, so the old check always chose bash).
case "${SHELL:-}" in
  */zsh) rc="$HOME/.zshrc" ;;
  *)     rc="$HOME/.bashrc" ;;
esac
# Match loosely (any existing line that puts ~/bin on PATH counts, however it's quoted:
# $HOME/bin, ${HOME}/bin, ~/bin), so re-running install.sh never appends a duplicate.
grep -qE '(HOME|~)/bin' "$rc" 2>/dev/null \
  || echo 'export PATH="$HOME/bin:$PATH"' >>"$rc"

echo "Installed outpost -> $HOME/bin/outpost"
echo "Run: source $rc"
echo "Next: outpost projects init   then   outpost base   then   outpost setup <project>"
echo "Tip: alias it for daily use, e.g.  echo 'alias ot=outpost' >> $rc"
