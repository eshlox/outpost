// Propagate package.json version -> VERSION and bin/outpost's OUTPOST_VERSION.
// Run automatically by `pnpm run version:packages` (after `changeset version`).
import { readFileSync, writeFileSync } from 'node:fs';

const root = new URL('..', import.meta.url);
const pkg = JSON.parse(readFileSync(new URL('package.json', root), 'utf8'));
const v = pkg.version;

writeFileSync(new URL('VERSION', root), v + '\n');

const binUrl = new URL('bin/outpost', root);
const bin = readFileSync(binUrl, 'utf8').replace(
  /^OUTPOST_VERSION=".*"$/m,
  `OUTPOST_VERSION="${v}"`,
);
writeFileSync(binUrl, bin);

console.log(`sync-version: ${v} -> VERSION, bin/outpost`);
