---
title: Tunnels
description: Expose dev servers via per-project Cloudflare tunnels.
---


A project can expose one or more of its dev servers on the public internet through
**its own Cloudflare named tunnel**. You declare the tunnel's routes in a
`tunnels.json` that lives **beside the project's `Dockerfile` on the host**
(`projects/<name>/tunnels.json`) - host-side config, like `compose.yaml`, not part
of the app repo. `outpost` mounts that dir read-only into the container at `/run/outpost`,
and two `just` recipes inside the container create and serve the tunnel.

The model is **one named tunnel per project** (named after the project) with **N
`hostname -> local-port` routes**. A single connector serves them all - you do not
run one process per port.

Routes come in two flavours, chosen per project in `tunnels.json`:

- **Fixed** (the default): every route has a `port`. `tunnel-setup` bakes the
  `hostname -> port` ingress into the config and `just tunnel` (no args) serves
  them all at once. This is what myapp/web use.
- **Dynamic**: a route **omits `port`** - one stable hostname whose target port you
  pick at run time. `tunnel-setup` only routes the hostname's DNS; `just tunnel
  <port>` then serves it at that port, **one port at a time**. Useful for a dev outpost
  that runs Vite, then Storybook, then a preview on different ports behind the same
  URL (e.g. mobile -> `https://localhost.example.dev`). Don't mix the
  two flavours in one `tunnels.json`.

## Declare the routes

```jsonc
// projects/myapp/tunnels.json
{
  // optional; defaults to the project name ("myapp"). Set it only to reuse
  // or share an existing named tunnel.
  "tunnel": "myapp",
  "routes": [
    { "hostname": "myapp.example.dev",     "port": 4323 },  // web (Astro)
    { "hostname": "api.myapp.example.dev", "port": 4321 }   // api
  ]
}
```

`port` is the **port your dev server binds inside the container** (the same port
you'd `EXPOSE`), since `cloudflared` runs in the container and reaches the app at
`http://localhost:<port>`. A project with no `tunnels.json` (or an empty `routes`)
simply has no tunnel - that's the "0 tunnels" case.

The hostnames must be on a zone in your Cloudflare account; `tunnel-setup` creates
the DNS records that point them at the tunnel.

## Use it (inside the container)

```bash
outpost sh myapp
just tunnel-setup     # once per project: login (first time), create tunnel,
                      # route each hostname's DNS, write the ingress config
just tunnel           # serve ALL routes (foreground; Ctrl-C stops). No ports.
```

`tunnel-setup` is re-runnable and reads `tunnels.json` each time, so editing the
file on the host and re-running picks up added/removed routes. The browser login
(`cloudflared tunnel login`) writes an **account-wide** `cert.pem`; you only do it
the first time you set up a tunnel in a given project's home volume.

Run the tunnel in **only one outpost at a time** for a given named tunnel - Cloudflare
load-balances across every connected connector, so two boxes running the same
tunnel would split traffic between them.

## What lives where

- `projects/<name>/tunnels.json` - on the host, beside the Dockerfile. The source
  of truth for the routes. Mounted read-only into the container at
  `/run/outpost/tunnels.json`.
- `~/.cloudflared/` in the project's **home volume** (`outpost-<name>-home`) - the
  account `cert.pem`, the tunnel's `<uuid>.json` credentials, and the generated
  `config.yml` (the ingress rules). These survive `outpost update`, like your other
  per-project state.

Because the credentials live in the per-project home volume, each project's tunnel
is independent: its own named tunnel, its own credentials, its own routes.

## Dynamic single-hostname tunnel (switchable port)

For a dev outpost where you want one stable public URL but keep moving it between dev
servers, declare a **port-less** route:

```jsonc
// projects/mobile/tunnels.json
{
  "tunnel": "localhost",                              // reuse/create a tunnel named "localhost"
  "routes": [ { "hostname": "localhost.example.dev" } ] // no "port" -> dynamic
}
```

```bash
outpost sh mobile
just tunnel-setup     # once: login (first time), create/route the hostname's DNS
just tunnel 5173      # localhost.example.dev -> http://localhost:5173 (Ctrl-C stops)
just tunnel 6006      # ... or point it at Storybook instead. One port at a time.
```

`tunnel-setup` writes a config with no ingress; each `just tunnel <port>` supplies
the target via `--url`, so switching ports is just Ctrl-C and re-run - no editing
`tunnels.json`. As with fixed tunnels, run it in only one outpost at a time.

## Ad-hoc, no setup

For a throwaway public URL (e.g. sharing a one-off or Expo phone testing) you don't
need `tunnels.json`:

```bash
just tunnel-quick 4321        # random https://<...>.trycloudflare.com -> :4321
```
