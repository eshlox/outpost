---
title: Installation
description: Install the outpost tool on your remote host.
---

outpost runs **on your remote Linux host**. You install it there once, then drive it over
SSH from your laptop. Prerequisites: Docker (with the Compose plugin), `git`, `socat` (for
the git agent bridge), and — ideally — a host user with uid 1000.

## 1. Install the tool

```sh
# on the host
git clone https://github.com/eshlox/outpost.git ~/outpost
~/outpost/install.sh
source ~/.bashrc          # or ~/.zshrc
```

`install.sh` symlinks `outpost` onto your `PATH` (`~/bin/outpost`). Verify:

```sh
outpost version
outpost doctor            # preflight: docker, socat, agent, uid, compose plugin, …
```

`outpost doctor` tells you what's missing. Common one-time host installs:

```sh
sudo apt update && sudo apt install -y socat tmux     # agent bridge + host dash
# Docker Engine + Compose plugin: https://docs.docker.com/engine/install/
```

See [Host provisioning](/guides/host-provisioning/) for a from-scratch host (Docker,
Tailscale, firewall) reference.

## 2. Daily alias (optional)

`outpost` is the canonical command. Most people alias it:

```sh
echo 'alias ot=outpost' >> ~/.bashrc && source ~/.bashrc
```

## 3. Connect with agent forwarding

From your laptop, SSH **with your agent forwarded** so git inside the box can sign and
authenticate without your key ever entering the container:

```sh
ssh -A dev-box            # dev-box is your ~/.ssh/config alias (see examples/ssh-config.example)
```

## Updating outpost

```sh
outpost upgrade           # git pull --ff-only in the tool repo
outpost base              # rebuild the base image
outpost update --all      # rebuild every project on it, keeping volumes
```

## Uninstall

Nothing outpost does is hidden, so teardown is a few explicit steps. Order matters:
destroy the projects (drops containers **and** their volumes), then remove the images, the
symlink, the `PATH` line, and the state dir.

```sh
# 1. Destroy every project (containers + code/home volumes + per-project networks).
#    'outpost ls' shows what exists first.
for p in $(outpost ls-projects); do outpost destroy "$p"; done

# 2. Remove the images (base + any leftover project images).
docker image rm outpost-base:latest 2>/dev/null || true
docker images --format '{{.Repository}}:{{.Tag}}' | grep '^outpost-' | xargs -r docker image rm

# 3. Remove the PATH symlink install.sh created.
rm -f ~/bin/outpost

# 4. Remove the PATH line install.sh appended to your rc (edit by hand, or:)
sed -i '\#HOME/bin#d' ~/.bashrc     # review the diff; adjust for ~/.zshrc / a custom line

# 5. Remove the host-only state dir (the agent-bridge sockets).
rm -rf "${XDG_RUNTIME_DIR:-/tmp}/outpost" "/tmp/outpost-$(id -u)"

# 6. Delete the tool checkout itself (and, if you want, your projects dir — it's YOUR repo).
rm -rf ~/outpost
# rm -rf ~/outpost-projects        # ONLY if you don't want to keep your project configs
```

Your project configs (`~/outpost-projects`) are your own git repo — deleting them is
optional and separate from removing the tool.

Next: [Quickstart](/quickstart/).
