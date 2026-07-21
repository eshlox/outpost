# Mutagen sshd (edit on your laptop, build in the box)

Sometimes you want to **edit on your laptop** (native editor, iOS Simulator / Android
emulator there) while the code lives on a **real Linux filesystem in the box** for builds.
[Mutagen](https://mutagen.io) syncs the two, but it needs an SSH endpoint — and an outpost
container has none and binds no port.

The `outpost-sshd` helper prepares a **rootless** `sshd` that Mutagen drives in inetd mode
over `docker exec` — one session per connection, **no daemon, no listening port**, so it
stays within the container's hardening (`cap_drop ALL` + `no-new-privileges`). Mutagen
connects via a ProxyCommand like:

```
docker exec -i -u ubuntu outpost-<project> /usr/sbin/sshd -i -f ~/.ssh/sshd_config
```

## Enable it for a project

`outpost-sshd` is **baked into every base image** — you don't copy any script. A project
opts in just by installing `openssh-server` (the base carries the ssh *client* only, to
stay lean):

```dockerfile
USER root
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
  && rm -rf /var/lib/apt/lists/*
USER ubuntu
```

That's it. The shell rc runs `outpost-sshd --ensure` on every `outpost sh` **only where
`sshd` is installed**, so the host key + config + your authorized key are always ready in
the projects that opted in, and it's a no-op everywhere else. Full topology and the
laptop-side Mutagen setup are in `docs/mutagen-sync.md`.

Check status inside the box: `outpost-sshd status`.
