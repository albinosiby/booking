# BookingOS public landing page

The public marketing homepage, extracted from the existing `bookingos/web/src/app/landing/page.tsx` project into its own folder. It preserves the landing design, original hero video, poster, logo, product mockups, design tokens and animations. It does not include the old project's operator console, authentication implementation, database clients or environment files.

## Develop and build

Requires Node.js 22+ and npm.

```sh
cd landing-page
npm ci
npm run dev
```

Open `http://127.0.0.1:3200`. For production:

```sh
npm run build
npm run typecheck
```

The build exports static files to `out/`. No environment variables, database credentials or additional Node server are needed to serve the exported landing page.

To preview the production export locally:

```sh
python3 -m http.server 3200 --bind 127.0.0.1 --directory out
```

The build's final step moves Next.js's exported assets into `out/_landing/_next/`, matching their public URL prefix. Serve the completed `out/` directory, not `.next/`.

## Shared Railway service

The intended routing for the combined container is:

| Path | Application |
| --- | --- |
| `/` | This landing page (`out/index.html`) |
| `/_landing/*` | This landing page's static scripts, styles, logo, poster and video |
| `/app/*` | Flutter owner/staff web app |
| `/admin/*` | Next.js admin panel |
| `/<organisation-slug>` and booking subpaths | Existing Next.js public booking website |
| `/api/sites/*` | Existing public booking website's API proxy |
| `/_next/*` | Existing public booking website's scripts and styles |

The landing page's links use full document navigation: **Sign in** opens `/app/sign-in`, and **Start free** opens `/app/register`. These destinations require the combined gateway and Flutter build; running the landing page alone does not provide them. The former old-project Templates links now open the landing page's Product preview section.

Serve `/` from this static export and forward the booking paths to `booking-website`; its generic root placeholder is not the product homepage. Do not use a catch-all landing-page fallback for organisation booking routes or missing assets.

The repository-root Dockerfile builds this export into the shared Railway image. Its gateway serves this page at `/`, keeps `/_landing/` separate from the booking server, serves Flutter under `/app/`, and forwards `/admin/` to the admin server. See [Railway deployment](../docs/railway-deployment.md) for the complete setup. Connecting an apex domain later will not require changing these relative links.

## Content and operations

The source marketing text is preserved. It describes capabilities such as online payments and WhatsApp automation that must be checked against the current product before publishing; copying the page does not implement those capabilities.

Serve the export over HTTPS with security headers from the gateway. Never include customer data, authentication tokens or server secrets in these static files. Use the same deployment revision as the other frontends and retain the previous container image for rollback. No schema change or migration is needed for this landing page.
