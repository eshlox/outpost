# Egress lock — restrict a box's outbound network

> A starting **recipe**, not a turnkey feature. Egress control here is
> *defense-in-depth* layered on top of outpost's container isolation (`--cap-drop ALL`,
> `--security-opt no-new-privileges`, no host Docker socket, per-project network, no
> forwarded private key). It reduces blast radius; it is not a hard security boundary on
> its own. Read the honesty notes before you rely on it.

## The threat

An outpost box already can't reach your laptop, your SSH private key, the host Docker
socket, or other projects. But by default it *can* still reach the whole internet. For
the "let an agent run YOLO" workflow that leaves two live risks:

- **Exfiltration.** A compromised dependency, a malicious `postinstall`, or an agent that
  has been prompt-injected can read your `/workspace` (your source, `.env` files, tokens
  you pasted) and POST it to an attacker-controlled endpoint.
- **Command-and-control / drop-in.** The same code can pull a second-stage payload or beacon
  to a C2 host.

Neither needs any privilege escalation — plain outbound HTTPS is enough. The fix is to
allow only the destinations your dev loop actually needs (GitHub, npm, PyPI, your own
APIs) and drop the rest.

Two approaches below. **Approach B (egress proxy) is the one to reach for** — it filters by
domain, which is what you actually want. Approach A is here because it needs nothing inside
the box, but IP-allowlisting modern CDNs is coarse and fragile.

---

## Approach A — host firewall on the project network (`DOCKER-USER`)

Filter the project's traffic on the **host**, in Docker's `DOCKER-USER` iptables chain
(the one chain Docker guarantees it won't clobber). No changes inside the box; nothing the
box can undo, since it has no privileges and isn't on the host network namespace.

Scope every rule to **this project's bridge interface** so you don't touch other projects
or the host's own traffic. Find the interface from the network id:

```bash
# <project> = your outpost project name
netid="$(docker network inspect "outpost-<project>-net" -f '{{.Id}}')"
brif="br-${netid:0:12}"          # Docker names the bridge br-<first 12 of the network id>
ip -brief link show "$brif"      # sanity check it exists
```

> If you set `com.docker.network.bridge.name` on the network the interface has your custom
> name instead — read it with
> `docker network inspect outpost-<project>-net -f '{{index .Options "com.docker.network.bridge.name"}}'`.

Then install an allowlist chain (run as root on the host). This uses the `iptables`
command; on an nftables host the `iptables-nft` shim writes the same rules — both work
because Docker still creates `DOCKER-USER`.

```bash
brif="br-xxxxxxxxxxxx"           # from above

# A dedicated chain so this is idempotent and easy to remove.
iptables -N OUTPOST_EGRESS 2>/dev/null || iptables -F OUTPOST_EGRESS

# 1. Let replies to connections the box opened come back.
iptables -A OUTPOST_EGRESS -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
# 2. DNS (so name resolution still works). See the DNS caveat below.
iptables -A OUTPOST_EGRESS -p udp --dport 53 -j RETURN
iptables -A OUTPOST_EGRESS -p tcp --dport 53 -j RETURN

# 3. Allowlist of destination ranges. THESE ARE EXAMPLES — verify current ranges yourself
#    (GitHub publishes https://api.github.com/meta; npm/PyPI sit behind Fastly/Cloudflare
#    and change without notice). This is the coarse, fragile part.
iptables -A OUTPOST_EGRESS -d 140.82.112.0/20 -j RETURN   # GitHub
iptables -A OUTPOST_EGRESS -d 143.55.64.0/20  -j RETURN   # GitHub
# iptables -A OUTPOST_EGRESS -d <fastly/cloudflare range> -j RETURN  # npm / PyPI CDN (huge, shared)

# 4. Drop everything else from this project's containers.
iptables -A OUTPOST_EGRESS -j DROP

# 5. Hook it in, scoped to THIS project's bridge (traffic ingressing the host from the box).
iptables -C DOCKER-USER -i "$brif" -j OUTPOST_EGRESS 2>/dev/null \
  || iptables -I DOCKER-USER -i "$brif" -j OUTPOST_EGRESS
```

Remove it again:

```bash
iptables -D DOCKER-USER -i "$brif" -j OUTPOST_EGRESS
iptables -F OUTPOST_EGRESS && iptables -X OUTPOST_EGRESS
```

**Be honest about what this buys you:**

- **IP-allowlisting CDNs is coarse and fragile.** npm (`registry.npmjs.org`) and GitHub's
  raw/release content sit behind Fastly, Cloudflare and Azure edges — huge, shared ranges
  that also serve millions of *other* sites, and that rotate. You end up either allowing a
  giant slice of the internet (so exfil to any Cloudflare-fronted host still works) or
  breaking installs when a range moves. There is no clean IP set for "npm and PyPI".
- **DNS caveat.** Docker gives containers an embedded resolver at `127.0.0.11` that the
  daemon forwards on their behalf, so the upstream DNS may not even traverse `$brif`; and
  allowing port 53 at all leaves a DNS-tunnelling exfil channel open. Domain filtering
  (approach B) sidesteps this.
- These rules are **not persistent** across host reboot / docker restart on their own —
  wire them into your firewall management (a systemd unit, `iptables-persistent`, or your
  nftables ruleset) if you want them to survive.

Use approach A when you want a blunt "this box may only talk to a couple of fixed IP
ranges" and can live with the fragility. Otherwise use B.

---

## Approach B — an egress-proxy sidecar (domain allowlist)

Run a small forward proxy ([tinyproxy](https://tinyproxy.github.io/)) as an outpost
**service** on the project network, with an explicit **domain** allowlist. Point the box's
`HTTPS_PROXY`/`HTTP_PROXY` at it. Now outbound HTTP(S) is allowed per *hostname*
(`registry.npmjs.org`, `.github.com`, …) instead of per IP range — exactly the granularity
you want, and it survives CDN IP churn.

Files in this directory (copy all three into your project):

- [`compose.yaml`](compose.yaml) — the `egress-proxy` service on `outpost-<project>-net`.
- [`tinyproxy.conf`](tinyproxy.conf) — proxy config; default-deny with a domain allowlist.
- [`allowlist.filter`](allowlist.filter) — the allowed domains
  (`.github.com`, `.githubusercontent.com`, `registry.npmjs.org`, `.pypi.org`,
  `files.pythonhosted.org`).

### 1. Drop the files into your project

This is a snippet, not a standalone project. Copy `compose.yaml`, `tinyproxy.conf` and
`allowlist.filter` into your real project directory (`outpost projects path`/`<project>/`),
beside its `Dockerfile`. If the project already has a `compose.yaml`, merge the
`egress-proxy` service into it (keep a single `services:` and `networks:` block). The proxy
has to be on **your project's** network — that's why it can't just live in this example dir.

### 2. Start it

```bash
outpost up <project>          # starts egress-proxy on outpost-<project>-net
outpost ps <project>          # confirm it's running
```

The compose lint passes because nothing is published, no host paths escape the project dir
(the bind sources are relative), and no host-escalating settings are requested.

### 3. Point the box at the proxy

Inside `outpost sh <project>`, or better, bake it into the project so every session and
subprocess inherits it. The box resolves `egress-proxy` by name on the project network:

```bash
export HTTPS_PROXY="http://egress-proxy:8888"
export HTTP_PROXY="http://egress-proxy:8888"
# Talk directly (no proxy) to your own backing services + localhost:
export NO_PROXY="localhost,127.0.0.1,db,redis,egress-proxy,.svc,.local"
# lowercase forms too - some tools only read these:
export https_proxy="$HTTPS_PROXY" http_proxy="$HTTP_PROXY" no_proxy="$NO_PROXY"

# git over HTTPS (if you use HTTPS remotes rather than SSH):
git config --global http.proxy "$HTTPS_PROXY"
```

To make it permanent, add those `export`s to the home volume's `~/.bashrc`, or set them as
`ENV` in the project's `Dockerfile`:

```dockerfile
ENV HTTPS_PROXY=http://egress-proxy:8888 \
    HTTP_PROXY=http://egress-proxy:8888 \
    NO_PROXY=localhost,127.0.0.1,db,redis,egress-proxy
```

npm, pip/uv, curl, and most agent runtimes read these variables. pip also honors
`PIP_INDEX_URL`; npm reads `npm_config_proxy`/`npm_config_https_proxy` if a tool ignores
the standard vars.

### 4. Verify

```bash
# allowed -> 200-ish
curl -sSI https://registry.npmjs.org/ | head -1
# denied -> tinyproxy returns 403 Forbidden (its "Filtered" page), not a real response
curl -sS https://example.com/ | head -20
```

### Extending the allowlist

Add the exact domains your toolchain needs to `allowlist.filter` (one anchored regex per
line), then `outpost down <project> && outpost up <project>`. Keep it minimal — every entry
is a place exfil could hide. Common additions: your own API/host, a private registry, an LLM
API endpoint your agent calls.

**Honesty notes for approach B:**

- It only governs traffic that **goes through the proxy**. A process that ignores the proxy
  env vars and opens a raw TCP socket to an IP is not stopped by tinyproxy. Combine B with A
  (drop non-proxied egress at the firewall, allow only the proxy's own outbound) for a real
  default-deny — the proxy makes the allowlist *manageable*, the firewall makes it
  *enforced*. This example ships them separately so you can start with either.
- tinyproxy sees the **hostname**, not full URLs, for HTTPS (it's a CONNECT tunnel). So it's
  "allow all of `github.com`", not "only these paths". That's fine for this threat model.
- Pin and vet the proxy image (see the note in `compose.yaml`). Don't trade an unpinned CDN
  for an unpinned container image.
- The proxy runs on the **host engine as root**, like all outpost services — the same trust
  level `outpost up` already warns about. Review `compose.yaml` before running it.
