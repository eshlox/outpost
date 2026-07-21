# attack-lab — watch the container boundary hold

A harmless, reproducible lab. You run a handful of commands **inside**
`outpost sh attack-lab` that *try* to do the things the sandbox is supposed to prevent —
steal your SSH key, reach the host Docker daemon, read another project, escalate to root —
and watch each one **fail**. Nothing here is destructive and nothing phones anywhere real
(`example.com` / localhost placeholders only).

This is a demo of outpost's actual hardening, not a claim of perfection. It shows the
default posture set in `bin/outpost`:

```
--user ubuntu  --cap-drop ALL  --security-opt no-new-privileges:true
--network outpost-<project>-net        # per-project, isolated
-e SSH_AUTH_SOCK=/run/agent/agent.sock # a forwarded agent SOCKET, never the key
-v outpost-<project>-code:/workspace   # only THIS project's volumes
-v outpost-<project>-home:/home/ubuntu
-v <agent-dir>:/run/agent:ro           # the agent bridge, read-only
# no /var/run/docker.sock, no docker client, no extra capabilities
```

## Setup

```bash
outpost projects new attack-lab       # or copy this dir into your projects dir
# (this example's Dockerfile is just FROM outpost-base:latest)
outpost setup attack-lab
outpost sh attack-lab
```

Run the checks below inside that shell. Expected output follows each; exact wording varies
by tool version, but the *outcome* (failure) is the point.

---

## 1. Steal the SSH private key → only the agent SOCKET is here

git inside the box works, so people assume the key is in the box. It isn't. outpost
forwards your ssh **agent** over a read-only bridge socket; the private key never leaves
your laptop.

```bash
echo "$SSH_AUTH_SOCK"           # /run/agent/agent.sock  (a socket, not a key)
ls -l /run/agent                # agent.sock, mounted read-only (ro)
ssh-add -L                      # lists PUBLIC keys the agent offers - no private material
find / -name 'id_*' -o -name '*.pem' 2>/dev/null | grep -vi '\.pub$'   # (nothing useful)
ls -la ~/.ssh 2>/dev/null       # known_hosts/config maybe; NO id_ed25519 / id_rsa private key
```

Expected: `$SSH_AUTH_SOCK` points at `/run/agent/agent.sock`; `ssh-add -L` prints only
`ssh-ed25519 AAAA... ` public lines (or "The agent has no identities."); the `find` turns
up no private key. A thief in the box can *use* the agent while the box is running (that's
by design — see the honesty note at the end), but cannot copy the key out.

## 2. Reach the host Docker socket → it isn't mounted, and there's no client

The classic container escape is talking to the host's `/var/run/docker.sock`. outpost never
mounts it, and the base image ships no docker client.

```bash
ls -l /var/run/docker.sock      # No such file or directory
docker ps                       # bash: docker: command not found
curl -sS --unix-socket /var/run/docker.sock http://x/version   # can't connect - no socket
```

Expected: the socket is absent, `docker` is not installed, and the curl to the unix socket
fails. There is no host daemon to talk to from here. (outpost runs your *services* on the
host engine itself via `outpost up` — the box never drives Docker.)

## 3. Read another project's files → other projects' volumes aren't mounted

Each project gets its own `outpost-<project>-code` and `outpost-<project>-home` volumes,
and only its own are mounted. There is no docker client to list or mount the others.

```bash
mount | grep -E '/workspace|/home/ubuntu'   # only THIS project's two volumes
ls /workspace /home/ubuntu                   # your project only
ls / 2>/dev/null                             # no other-project mountpoints
docker volume ls                             # bash: docker: command not found
```

Expected: you see only `attack-lab`'s own `/workspace` and `/home/ubuntu`. Another project's
`outpost-otherproject-home` volume is simply not present in this container's mount table,
and with no Docker client there's no way to attach it. (Data on a *shared backing service*
you both connect to — e.g. one Postgres — is a different matter; isolation is per project's
network + volumes, not a claim that two projects pointed at the same DB can't see it.)

## 4. Escalate privileges → no caps, no new privileges, no sudo

The container drops **all** Linux capabilities and sets `no-new-privileges`, so setuid
binaries can't hand you more than you started with, and privileged syscalls fail.

```bash
# Capability set is empty (all zeros = no capabilities):
grep Cap /proc/self/status
#   CapInh: 0000000000000000
#   CapPrm: 0000000000000000
#   CapEff: 0000000000000000
#   CapBnd: 0000000000000000   <- ALL dropped
#   CapAmb: 0000000000000000
capsh --print 2>/dev/null || echo "(capsh not installed - /proc/self/status above is the proof)"

# sudo: not installed, and even if it were, no-new-privileges blocks the setuid escalation:
sudo -n true                    # bash: sudo: command not found

# A privileged operation: mounting needs CAP_SYS_ADMIN, which is dropped:
mount -t tmpfs none /mnt 2>&1   # mount: only root can do that / permission denied

# Raw network sockets need CAP_NET_RAW, also dropped (ping isn't installed in the base;
# if you install iputils-ping it STILL fails to open the raw socket):
ping -c1 127.0.0.1 2>&1 || echo "ping unavailable / CAP_NET_RAW dropped - expected"
```

Expected: `CapBnd`/`CapEff` are all-zero (compare to a normal container, which shows
`00000000a80425fb`); `sudo` is not found; `mount` is refused; raw sockets are unavailable.
You are uid 1000 (`id`) with no route to uid 0.

> **Depends on host config:** the box runs as `--user ubuntu` (uid 1000). Reading the
> forwarded agent in step 1 assumes your host user is also uid 1000 (outpost warns at `sh`
> time if it isn't). The capability drop and `no-new-privileges` here do **not** depend on
> host uid — they're container flags.

## 5. (Optional) A mock-malicious `postinstall` → it finds nothing to steal

Simulate the supply-chain attack the whole design is aimed at: a package whose install hook
tries to read your secrets and exfiltrate them. Everything below is inert — the "exfil"
target is `example.com` and the payload just reports what it *couldn't* find.

```bash
mkdir -p /tmp/evil-dep && cd /tmp/evil-dep
cat > package.json <<'JSON'
{
  "name": "evil-dep",
  "version": "1.0.0",
  "scripts": {
    "postinstall": "node ./steal.js"
  }
}
JSON
cat > steal.js <<'JS'
// Mock-malicious postinstall. Reads NOTHING sensitive because there's nothing to read,
// and "exfiltrates" to example.com (a placeholder that ignores it). Purely illustrative.
const fs = require("fs"), os = require("os");
const loot = [];
try {
  const dir = os.homedir() + "/.ssh";
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith(".pub") && /^id_|\.pem$/.test(f)) loot.push(dir + "/" + f);
  }
} catch (_) {}
console.log("would exfiltrate private keys:", loot.length ? loot : "(none found)");
console.log("SSH_AUTH_SOCK present:", !!process.env.SSH_AUTH_SOCK, "(a socket, not a key)");
console.log("docker socket present:", fs.existsSync("/var/run/docker.sock"));
console.log("target (placeholder, no request sent): https://example.com/collect");
JS

npm install --ignore-scripts=false   # runs the postinstall
```

Expected: `would exfiltrate private keys: (none found)`, `docker socket present: false`.
The hook runs with your box's full privileges — and still comes up empty, because the
sensitive material was never in the box to begin with. Clean up: `cd ~ && rm -rf /tmp/evil-dep`.

---

## What this does and does not prove

- **Holds:** private key stays on your laptop; no host Docker socket; other projects' volumes
  aren't mounted; no capabilities; no privilege escalation; per-project network.
- **By design, NOT prevented (be honest):**
  - While the box is running, any process in it can **use** the forwarded agent to sign/push
    as you. Mitigate with a *separate* dev-box key or a per-use-confirm agent (e.g. Secretive)
    — see `docs/git-and-ssh.md`.
  - The box can read **its own** `/workspace` and `/home/ubuntu` — that's the whole point of a
    dev box. Don't paste secrets into a box you let an agent run wild in.
  - Without egress control the box can still reach the internet (that's what
    [`../egress-lock/`](../egress-lock/) is for).
  - This is Docker's default isolation, not a microVM. It's a strong, honest boundary for the
    "run an agent without handing over my laptop" threat model — see `docs/concepts/security.md`.
