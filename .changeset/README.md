# Changesets

This folder is managed by [changesets](https://github.com/changesets/changesets).

To record a change for the next release:

```sh
pnpm changeset      # describe the change + pick a bump (patch/minor/major)
```

Commit the generated `.changeset/*.md` file with your PR. On merge to `main`, the Release
workflow opens (or updates) a "Version Packages" PR; merging that bumps the version,
updates `CHANGELOG.md` and `VERSION`/`bin/outpost`, and tags the release.
