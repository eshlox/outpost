# Contributing to outpost

Thanks for your interest! outpost is intentionally small and readable — a single bash
script plus a docs site — so contributing is low-ceremony.

## Ground rules

- **Keep it readable.** The whole tool is `bin/outpost`, and the point is that you can read
  it. Prefer clear bash over clever bash. Match the surrounding style and comment density.
- **The tool guesses nothing.** A project is a `Dockerfile` plus optional plain files. Avoid
  adding magic, auto-detection, or hidden lifecycle.
- **No new runtime dependencies** for the tool beyond what `outpost doctor` already checks
  (docker, git, socat, tmux). The base image's tooling is fair game.

## Dev loop

```sh
shellcheck bin/outpost install.sh shared/bootstrap-user.sh shared/sshd.sh
bash tests/smoke.sh        # drives bin/outpost against a mock engine — no Docker needed
```

The smoke test (`tests/smoke.sh` + `tests/mock-docker`) asserts name validation, the
generated `docker run` args, the host-escalation compose lint, `ports`, `update`, the
`outpost projects` commands, and a clean `destroy`. Add a case when you change behaviour.

For the docs site:

```sh
cd docs && pnpm install && pnpm run dev    # http://localhost:4321
pnpm run build                             # must pass in CI
```

## Pull requests

1. Branch from `main`.
2. Make the change; keep the smoke test and `shellcheck` green; update the docs under
   `docs/src/content/docs/` if behaviour changes.
3. Run `pnpm changeset` and commit the generated `.changeset/*.md` (pick patch/minor/
   major). This drives the version bump and changelog on release.
4. Open the PR with a clear description of the *why*.

## Releases

Maintainers: merging PRs accumulates changesets. The Release workflow opens a "Version
Packages" PR; merging it bumps the version, writes `CHANGELOG.md` + `VERSION` +
`bin/outpost`, and tags the release. Nothing is published to a package registry — outpost is
a `git clone` + `install.sh` tool.

By contributing you agree your contributions are licensed under the [MIT License](LICENSE).
