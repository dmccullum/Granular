# Filmify Website

The public landing page for [Filmify](https://github.com/dmccullum/Filmify), a native macOS app for adding a film-like finish to still images.

## Local development

Requires Node.js 22.13 or newer.

```bash
pnpm install
pnpm dev
```

The site is available at the local address printed by the development server.

## Build

```bash
pnpm build
```

The page is built with React and vinext. Its motion effects respect the system’s Reduce Motion preference.
