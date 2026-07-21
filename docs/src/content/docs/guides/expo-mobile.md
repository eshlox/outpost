---
title: Mobile testing with Expo
description: Testing iOS/Android with Expo + EAS.
---


The hard rule first: **iOS Simulator and the Android emulator cannot run on a
Linux host.** The Simulator needs macOS + Xcode; the emulator needs host
hardware acceleration. So no container or your host outpost runs them - ever. What CAN
run remotely is the part you actually want isolated: `npm install`, the Metro
bundler, builds, tests, and the agents.

So the split for an Expo project is:

| Runs in the outpost (your host) | Runs on your Mac |
|---|---|
| `npm/pnpm install`, dependency code | Xcode, iOS Simulator |
| Metro / `expo start` bundler | Android emulator |
| your YOLO agents | a physical phone over USB |
| `eas build` / `eas submit` (just the CLI; build runs in EAS cloud) | what you LOOK at |

## Option 1 (recommended): physical phone + tunnel to the outpost

Your real device connects to the Metro bundler running in the container, over a
public tunnel, from anywhere. No Mac build toolchain needed for JS-only changes.

In the project container (`outpost sh <project>`):

```bash
npm i -g @expo/ngrok          # one-time: --tunnel needs this (else it hangs/prompts)
npx expo start --tunnel       # a dev server reachable from your phone over the internet
```

`--tunnel` uses **ngrok** to expose the bundler at a public `*.exp.direct` URL, so
Expo Go (or your dev client) on the phone reaches it without being on the same
network. Without `@expo/ngrok` installed, the command errors and tries to prompt -
so install it first (or bake it into the base image). Scan the QR code in Expo Go
(or your custom dev client) and the app loads, with fast refresh.

Note that the tunnel exposes your bundler on a public URL while it runs; stop it
when you are done.

If you prefer your own tunnel, the base image ships `cloudflared`: run the dev
server normally and `cloudflared tunnel --url http://localhost:<port>` for an
`https://<random>.trycloudflare.com` URL.

This covers the everyday loop: edit JS in the outpost, agents work in the outpost, see it
live on your phone. Latency is a little higher than LAN but fine for iteration.

## Option 2: native builds without a Mac - EAS Build (cloud)

When you need a real signed iOS/Android binary (native module changes, store
builds, a custom dev client), use EAS Build. It compiles in Expo's cloud on
macOS/Linux build workers, so you do not need local Xcode/Android Studio. From
the outpost:

```bash
npm i -g eas-cli                     # (or bake into the base / install per project)
eas login                            # alias of eas account:login
npx expo install expo-dev-client     # required before a development build
eas build --platform android         # or ios, or all
eas build --platform ios --profile development   # a custom dev client
```

- iOS builds require Apple credentials; EAS can manage signing for you or use
  credentials you provide. A real-device iOS build still needs an Apple Developer
  account.
- A **development build** (`--profile development`) gives you a custom dev client
  you install on the phone, then `npx expo start --dev-client --tunnel` from the
  outpost drives it - same remote loop as Option 1 (so the same `@expo/ngrok`
  prerequisite applies). It is for apps with native modules Expo Go does not
  include. Install `expo-dev-client` in the project first (shown above).
- For an iOS **Simulator** dev build specifically, set `ios.simulator: true` on
  the `development` profile in `eas.json` (otherwise you get a device build that
  needs a registered device). You still run that simulator build on the Mac
  (Option 3), not on the outpost.
- `eas submit` ships a finished build to TestFlight / Play Console from the CLI.

## Option 3: the Mac for the tight simulator loop

When you specifically want the iOS Simulator (fastest visual loop, no phone),
that part is a Mac-local activity. Two clean ways:

- Keep a LOCAL copy of the same project (same approach, local Docker/OrbStack)
  for simulator work, and let the outpost handle agents/long tasks. The setup is
  identical, so this is just "run the container locally" when you need the
  simulator.
- Or run only Metro locally on the Mac and the Simulator against it, accepting
  that local Metro runs your JS deps on the Mac. Prefer the first option to keep
  dependency execution boxed.

## Practical recommendation

- Day to day: Option 1 (phone + `--tunnel` from the outpost). Most Expo work is JS,
  and this keeps install/build/agents isolated on your host.
- Native binaries / store builds: Option 2 (EAS Build), no Mac toolchain needed.
- iOS Simulator when you want it: Option 3, on the Mac, using your local copy.

The one thing to internalize: the outpost bundles and builds; the Mac (or your phone)
is what you look at.
