---
title: Edit on your laptop (Mutagen)
description: Edit on your laptop, build in the box, over a rootless sshd.
---


The mobile loop has a split the public tunnels in [expo-mobile.md](/guides/expo-mobile/)
don't cover: you want the repo **on the Mac** (so Xcode / the iOS Simulator / the
Android emulator see real files) *and* the same repo **in the outpost** (so
`pnpm install`, Metro, builds, and the agents run on your host, isolated).
[Mutagen](https://mutagen.io) keeps the two in sync. To reach the outpost it needs an
SSH endpoint that lands in `/workspace` as `ubuntu`, and the container doesn't run
one by default - `outpost-sshd` provides it. The helper is baked into every base
image; a project opts in just by installing `openssh-server` in its Dockerfile.

This example uses **myapp**. To add it to another project, install `openssh-server`
in that project's Dockerfile - nothing to copy (see `examples/mutagen-sshd`).

## Which transport, and why

Use Mutagen's **SSH transport**, not its Docker transport.

- The **Docker transport** (`docker://…`) installs its agent by `docker cp` (lands
  the binary root-owned) and then `chown`s it to `ubuntu` - which needs `CAP_CHOWN`.
  outpost runs every container with `--cap-drop ALL`, so the chown fails with
  `unable to set ownership of copied file`. It's a dead end under outpost's hardening.
- The **SSH transport** writes its agent *as `ubuntu`, into `ubuntu`'s own home* -
  owned correctly on creation, no chown, no capability needed. It's the transport
  that fits the threat model.

We also reach the container by its **stable name** (`outpost-myapp`, which outpost keeps
across every recreate) over a `docker exec … sshd -i` ProxyCommand - so there's **no
published port to look up** and nothing to re-check after `outpost update`. And auth uses
a **dedicated public key** you authorize once; no private key is ever copied.

## Topology

```
Mac ──ProxyCommand──▶ ssh dev@dev-box (your host, Tailscale) ──▶ docker exec -u ubuntu outpost-myapp sshd -i ──▶ /workspace
    (Mutagen, SSH transport)                                    (per-connection, no listening port)
```

`sshd -i` is inetd mode: one SSH session served over the `docker exec` stdio. No
port binds, so the dynamic host port (`outpost ports myapp`) is irrelevant here.

---

## One-time setup

### 1. In the outpost: make the sshd files exist

`outpost-sshd` (auto-run by the shell rc on every `outpost sh`) generates the host key and
writes `~/.ssh/sshd_config` - the two things `sshd -i` needs. Just enter the outpost once:

```bash
ssh -A dev-box
outpost sh myapp        # the rc runs `outpost-sshd --ensure`, creating ~/.ssh/{ssh_host_ed25519_key,sshd_config}
```

(The host key lives in the home volume, so it survives `outpost update` - the Mac keeps
trusting it, no host-key churn.)

### 2. On the Mac: install Mutagen

```bash
brew install mutagen-io/mutagen/mutagen
```

(No Docker needed for the SSH transport - `ssh` is built in.)

### 3. On the Mac: a dedicated SSH key for the outpost

Scope this sync to its own key, not your everything-key (matches
[security.md](/concepts/security/): "scope credentials per project"). Only the **public**
half ever reaches the container.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/myapp_box -C "myapp-outpost sync" -N ""
```

`-N ""` (no passphrase) is deliberate: an unattended sync that reconnects on its own
can't answer a passphrase prompt. The key only unlocks a disposable container reached
solely through your Tailscale ProxyJump, and FileVault protects it at rest. Prefer a
passphrase? Add one and `ssh-add` it into your agent.

### 4. On the Mac: `~/.ssh/config`

```text
Host myapp-outpost
  User ubuntu
  IdentityFile ~/.ssh/myapp_box
  IdentitiesOnly yes
  ProxyCommand ssh dev@dev-box.<your-tailnet>.ts.net docker exec -i -u ubuntu outpost-myapp /usr/sbin/sshd -i -f /home/ubuntu/.ssh/sshd_config
```

`IdentitiesOnly yes` makes `ssh` offer **only** this key - so auth is deterministic
and you never hit the "which key is it offering?" trap.

### 5. Authorize that key inside the container

Pipe the **public** key in and fix home perms (sshd's `StrictModes` rejects keys if
`~` or `~/.ssh` are group/other-writable). `>` overwrites, so `authorized_keys` ends
up holding *only* this scoped key:

```bash
cat ~/.ssh/myapp_box.pub | ssh dev@dev-box.<your-tailnet>.ts.net \
  'docker exec -i -u ubuntu outpost-myapp bash -c "umask 077; mkdir -p ~/.ssh && cat > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && chmod go-w /home/ubuntu /home/ubuntu/.ssh"'
```

`outpost-sshd` will **not** clobber this on later `outpost sh`es (it only bootstraps
`authorized_keys` from the forwarded agent when the file is empty).

### 6. Verify the connection

```bash
ssh myapp-outpost true        # exits cleanly = good. "Permission denied (publickey)" -> see Troubleshooting
```

---

## Create the sync

Sync **only the Flutter app**, not the whole monorepo - the Mac just needs the app
source for the Simulator, not the api/admin/web Node packages. And ignore every
build/cache tree: those are machine-specific, generated independently on each side.

> `--ignore-vcs` only skips `.git`; it does **not** honor `.gitignore`. List the
> caches explicitly or they get synced (e.g. an 800 MB `.pnpm-store`).

```bash
# adjust the path if the app isn't at apps/mobile:  ssh myapp-outpost 'ls /workspace/apps'
mutagen sync create --name=myapp-mobile \
  myapp-outpost:/workspace/apps/mobile \
  ~/projects/myapp-mobile \
  --ignore-vcs \
  --ignore=.dart_tool \
  --ignore=build \
  --ignore=.flutter-plugins \
  --ignore=.flutter-plugins-dependencies \
  --ignore=Pods \
  --ignore=.symlinks \
  --ignore=.gradle \
  --ignore=node_modules \
  --ignore=.idea \
  --ignore='*.iml' \
  --ignore=.DS_Store
```

The ignore patterns are **name-based**, so they match at any depth (`Pods` catches
`ios/Pods`, `build` catches `android/app/build`, etc.; `.idea`/`*.iml` catch the
JetBrains/IntelliJ project metadata each IDE regenerates locally) - no full paths
needed. You
sync `lib/`, `pubspec.yaml`/`pubspec.lock`, `ios/Runner`, `android/app/src`, assets;
each machine builds its own `.dart_tool`/`build`/`Pods`.

## Watch it / drive it

```bash
mutagen sync list  myapp-mobile    # status, file counts, conflicts, problems
mutagen sync monitor myapp-mobile  # live progress; Ctrl-C once it says "Watching for changes"
mutagen sync flush myapp-mobile    # force a round, block until in sync
mutagen sync pause/resume myapp-mobile
mutagen sync terminate myapp-mobile
```

`create` returns immediately and syncs in the **background**; wait for **Watching for
changes** before expecting files. To change the path or ignores later, `terminate`
and `create` again (sessions are immutable).

## Then build on the Mac

```bash
cd ~/projects/myapp-mobile
flutter pub get          # Mac builds its own .dart_tool / plugins
cd ios && pod install    # Mac builds its own Pods
flutter run              # against the iOS Simulator
```

Edit in the outpost (Helix, agents); changes land on the Mac in ~a second, and
`flutter run`'s own file watcher hot-reloads them. Keep running `pnpm`/`flutter`
on each side independently - never sync `node_modules`, `.pnpm-store`, or build output.

The outpost drives its Flutter side through **fvm** (the image bakes only the fvm binary;
the SDK lands in `~/fvm` in the home volume - see `templates/flutter/Dockerfile`). So
in the outpost you run `fvm flutter <cmd>` / `fvm dart <cmd>`, not bare `flutter`/`dart`:
on first use, `cd apps/mobile && fvm install && fvm flutter pub get` (fvm reads the
repo's `.fvmrc`). The outpost only does `pub get`/analyze/test/codegen for the agents - no
Android SDK or JDK there, since device + emulator builds stay on the Mac.

---

## Troubleshooting

**`Permission denied (publickey)`** - the key your Mac offers isn't authorized, or
`StrictModes` is rejecting it. Diagnose:

```bash
ssh -v myapp-outpost true 2>&1 | grep -Ei 'offering|denied'   # which key is offered?
```

- *Offered key isn't the one you seeded* - re-run step 5 with the right `.pub`
  (with `IdentitiesOnly yes` + a dedicated key this shouldn't happen).
- *Right key, still denied* - home perms. Re-run the `chmod go-w /home/ubuntu
  /home/ubuntu/.ssh` from step 5. Check with
  `ssh dev@dev-box.<your-tailnet>.ts.net 'docker exec -u ubuntu outpost-myapp ls -ld /home/ubuntu /home/ubuntu/.ssh'`.

**`unable to set ownership of copied file`** - you used the Docker transport
(`docker://…`); it can't work under `--cap-drop ALL`. Use the SSH transport above.

**`flutter pub get` fails after a scoped sync** - the app has a `path:` dependency
*outside* `apps/mobile` (a shared Dart package elsewhere in the monorepo). Either
also sync that package's dir, or fall back to a whole-repo sync with the same
`--ignore` list **plus** `--ignore=.pnpm-store`.

**Files never appear** - check the container side actually has the repo
(`ssh myapp-outpost 'ls /workspace/apps/mobile'`); outpost starts an empty workspace, so
you clone inside it first. Then confirm `mutagen sync list` shows it past staging.

## What lives where

- `~/.ssh/myapp_box{,.pub}` on the Mac - the dedicated sync key (private half
  never leaves the Mac).
- `~/.ssh/{ssh_host_ed25519_key,sshd_config,authorized_keys}` in the outpost's **home
  volume** (`outpost-myapp-home`) - generated by `outpost-sshd`, survive `outpost update`.
- `/usr/local/bin/outpost-sshd` - the rootless sshd helper, baked into the base
  image (from `shared/sshd.sh`); active in any project that installs `openssh-server`.

## Want Touch-ID gating instead?

The dedicated on-disk key isn't Touch-ID gated. To gate the sync with Secretive,
make a *new* Secretive key for the outpost, point the `myapp-outpost` block's
`IdentityAgent` at Secretive's socket (drop `IdentityFile`/`IdentitiesOnly`), and
seed that public key in step 5. The cost is a Touch-ID tap on every Mutagen
reconnect (sleep/wake, outpost restart, network blip) - fine for occasional use, mildly
annoying for an always-on sync. For a background sync, the scoped on-disk key is the
nicer trade.
