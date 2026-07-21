#!/usr/bin/env bash
# outpost-sshd - prepare a rootless sshd for Mutagen inside an outpost container, so
# you can edit on your laptop and build in the box (Mutagen syncs your repo to the
# container's /workspace as the `ubuntu` user).
#
# This helper ships in EVERY base image (baked from shared/sshd.sh) - you do NOT copy
# it into a project. A project OPTS IN just by installing openssh-server in its
# Dockerfile (the base carries the client only, to stay lean):
#   USER root
#   RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
#     && rm -rf /var/lib/apt/lists/*
#   USER ubuntu
# The shell rc runs `outpost-sshd --ensure` on every `outpost sh`, but ONLY where sshd
# is actually installed - a no-op in projects that didn't opt in. See examples/mutagen-sshd.
#
# Mutagen reaches the container by its STABLE name via a ProxyCommand that runs
#   docker exec -i -u ubuntu outpost-<project> /usr/sbin/sshd -i -f ~/.ssh/sshd_config
# i.e. sshd in inetd mode (`-i`) over the exec's stdio: one session per connection,
# NO listening port and NO daemon. That fits the container's hardening (cap_drop ALL
# + no-new-privileges) - non-root, no setuid. See docs/mutagen-sync.md.
#
# All this does is make sure the three things `sshd -i` needs exist:
#   - the host key (~/.ssh/ssh_host_ed25519_key),
#   - the config (~/.ssh/sshd_config),
#   - an authorized_keys with your laptop's PUBLIC key.
#
# Usage (idempotent):
#   outpost-sshd            prepare the files; print a one-line status
#   outpost-sshd --ensure   same, but quiet
#   outpost-sshd status     report what's ready
set -Eeuo pipefail

sshdir="$HOME/.ssh"
hostkey="$sshdir/ssh_host_ed25519_key"
authkeys="$sshdir/authorized_keys"
config="$sshdir/sshd_config"
quiet=""

log() { [ -n "$quiet" ] || echo "outpost-sshd: $*" >&2; }

write_config() {
  # Minimal, root-free sshd config for `sshd -i`. UsePAM no (PAM needs root);
  # privilege separation turns off when sshd runs non-root, so no setuid is attempted.
  cat >"$config" <<CFG
HostKey $hostkey
AuthorizedKeysFile $authkeys
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp internal-sftp
CFG
}

# authorized_keys policy:
#   - OUTPOST_SSHD_AUTHORIZED_KEYS set -> install that file (explicit clobber);
#   - else if authorized_keys is EMPTY -> bootstrap from the forwarded agent (ssh-add -L);
#   - else leave it ALONE - never clobber a key you seeded yourself from the laptop.
seed_authorized_keys() {
  if [ -n "${OUTPOST_SSHD_AUTHORIZED_KEYS:-}" ]; then
    install -m 600 "$OUTPOST_SSHD_AUTHORIZED_KEYS" "$authkeys"
  elif [ ! -s "$authkeys" ] && agent_keys="$(ssh-add -L 2>/dev/null)" && [ -n "$agent_keys" ]; then
    printf '%s\n' "$agent_keys" >"$authkeys"
    chmod 600 "$authkeys"
  fi
}

prepare() {
  install -d -m 700 "$sshdir"
  # Host key in the home VOLUME, so it survives `outpost update` (no host-key churn).
  [ -f "$hostkey" ] || ssh-keygen -q -t ed25519 -N '' -f "$hostkey" -C "outpost-box"
  write_config
  seed_authorized_keys
  [ -f "$authkeys" ] && chmod 600 "$authkeys"
  # StrictModes: sshd rejects keys if home or ~/.ssh are group/other-writable.
  chmod go-w "$HOME" "$sshdir" 2>/dev/null || true
}

case "${1:-}" in
  --ensure)
    quiet=1
    prepare
    ;;
  status)
    n=0; [ -s "$authkeys" ] && n="$(grep -c . "$authkeys" 2>/dev/null || echo 0)"
    echo "outpost-sshd: host key $([ -f "$hostkey" ] && echo present || echo MISSING)," \
         "config $([ -f "$config" ] && echo present || echo MISSING)," \
         "authorized_keys: $n key(s)"
    ;;
  ''|prepare)
    prepare
    if [ -s "$authkeys" ]; then
      log "ready - Mutagen connects via the docker-exec 'sshd -i' ProxyCommand (docs/mutagen-sync.md)."
    else
      log "host key + config ready, but no key authorized yet - seed your laptop's public key (docs/mutagen-sync.md)."
    fi
    ;;
  *)
    echo "usage: outpost-sshd [--ensure | status]" >&2; exit 2
    ;;
esac
