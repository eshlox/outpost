---
title: Backups & migration
description: Back up, restore, and move a project's named volumes to a new host.
---

outpost's durable state lives in **named Docker volumes**, two per project:

- `outpost-<project>-code` — mounted at `/workspace` (your repo, `node_modules`, build
  artifacts you keep).
- `outpost-<project>-home` — mounted at `/home/ubuntu` (dotfiles, agent auth + history,
  node/fnm, cloudflared creds, shell history).

The container is disposable and your project **configs** are already in your own git repo
(`outpost projects sync`). What those two things don't cover is the volume contents — so
backing up is just archiving these volumes. The pattern below uses a throwaway `ubuntu`
container to `tar` the volume to (or from) a file on the host; nothing about it is
outpost-specific, so it works even if outpost isn't installed on the other end.

## Back up

Run these from any host directory (the archive lands in `$PWD`):

```bash
# code volume -> web-code.tar.gz
docker run --rm \
  -v outpost-web-code:/d:ro -v "$PWD":/b \
  ubuntu tar czf /b/web-code.tar.gz -C /d .

# home volume -> web-home.tar.gz
docker run --rm \
  -v outpost-web-home:/d:ro -v "$PWD":/b \
  ubuntu tar czf /b/web-home.tar.gz -C /d .
```

`-C /d .` archives the volume's *contents* (not the `/d` directory), so the restore below
unpacks cleanly. Mounting the volume read-only (`:ro`) means the backup can't perturb it.

## Restore

Restore into a **fresh, empty** volume (create the project on the target first so the
volume names exist — `outpost setup web` will create them, or `docker volume create` them
by hand). Then unpack the inverse of the backup:

```bash
docker run --rm \
  -v outpost-web-code:/d -v "$PWD":/b \
  ubuntu tar xzf /b/web-code.tar.gz -C /d

docker run --rm \
  -v outpost-web-home:/d -v "$PWD":/b \
  ubuntu tar xzf /b/web-home.tar.gz -C /d
```

If you restored into a volume that a container already uses, recreate the container so it
mounts the restored data cleanly, and fix ownership (the volumes must be owned by uid 1000):

```bash
outpost rm web        # drop the container (keeps the volumes)
outpost setup web     # recreate on the restored volumes (fixes /workspace + /home ownership)
```

## Move a project to a new host

1. **On the old host** — back up both volumes as above, and make sure your project config is
   pushed: `outpost projects sync`.
2. **Copy the archives** to the new host (`scp web-code.tar.gz web-home.tar.gz newhost:`).
3. **On the new host** — install outpost, clone your projects repo (or
   `outpost projects init --remote …` and pull), then build the project so the volumes exist:

   ```bash
   outpost base            # if the base image isn't built yet
   outpost setup web       # builds the image, creates empty code/home volumes
   outpost rm web          # stop/remove the container so nothing is writing the volumes
   ```

4. **Restore into the new volumes** (the restore commands above), then bring it back:

   ```bash
   outpost setup web       # recreate the container on the restored volumes
   outpost sh web          # your workspace + home are exactly as they were
   ```

Because the project's `Dockerfile`/`compose.yaml`/`tunnels.json` came over via git and the
state came over via the volume archives, the box on the new host is a faithful copy — same
code, same agent auth/history, same dotfiles.

> **Disk usage.** Agents fill home volumes over time. Check a project's volumes with
> `docker system df -v | grep outpost-web` (or `outpost status web`, which surfaces
> code/home volume usage) before a machine's disk fills up.
