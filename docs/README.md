# outpost docs site

The documentation site, built with [Astro](https://astro.build) +
[Starlight](https://starlight.astro.build) and deployed to **Cloudflare Pages** at
<https://outpost.eshlox.net>.

## Local development

```sh
cd docs
pnpm install
pnpm run dev      # http://localhost:4321
pnpm run build    # static output -> docs/dist/
```

Content lives in `src/content/docs/` (Markdown/MDX). The sidebar and site config are in
`astro.config.mjs`.

## Deploy (Cloudflare Pages)

**Option A — Git integration (recommended).** In the Cloudflare dashboard, create a Pages
project connected to the repo with:

- **Root directory:** `docs`
- **Build command:** `pnpm install --frozen-lockfile && pnpm run build`
- **Build output directory:** `dist`

Then add the custom domain `outpost.eshlox.net` under the Pages project's *Custom domains*.
Every push to `main` redeploys.

**Option B — GitHub Actions.** See `.github/workflows/docs-deploy.yml`, which builds the
site and publishes it with `wrangler pages deploy`. It needs two repo secrets:
`CLOUDFLARE_API_TOKEN` (Pages: Edit) and `CLOUDFLARE_ACCOUNT_ID`.
