# Tunnels

Each project can expose its dev servers publicly through one **per-project Cloudflare
named tunnel**, declared in a `tunnels.json` that lives **beside the Dockerfile** (not in
the workspace). outpost mounts the project's config dir read-only at `/run/outpost`, and the
in-container `just tunnel-setup` / `just tunnel` recipes read it. One named tunnel per
project, with N `hostname → port` routes; one connector serves them all.

Requires a Cloudflare account and a domain on Cloudflare. First run does a one-time
browser login; credentials land in the home volume.

## Two flavours

**Fixed** — every route has a `port`. `tunnel-setup` bakes the ingress and `just tunnel`
(no args) serves them all:

```json
{
  "routes": [
    { "hostname": "web.example.dev", "port": 4323 },
    { "hostname": "api.example.dev", "port": 3333 }
  ]
}
```
See [`fixed.tunnels.json`](fixed.tunnels.json).

**Dynamic** — a route omits `port` (one stable hostname, port chosen at run time). Handy for
a box that runs Vite, then Storybook, then a preview behind the same URL. Serve one port at a
time with `just tunnel <port>`:

```json
{
  "tunnel": "myproject",
  "routes": [ { "hostname": "myproject.example.dev" } ]
}
```
See [`dynamic.tunnels.json`](dynamic.tunnels.json). Don't mix flavours in one file.

## Use it

```sh
outpost projects edit <name> tunnels   # create/edit tunnels.json beside the Dockerfile
outpost sh <name>
just tunnel-setup                       # once per project: login (first time), create, route DNS
just tunnel                             # fixed: serve all routes   |   dynamic: just tunnel <port>
```

For a throwaway URL with no setup (any port): `just tunnel-quick <port>`.
