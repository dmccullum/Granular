# Filmify

Filmify is a native macOS instant-processing and watched-folder utility for applying film-like tone and color, optical light shaping, lens diffusion, restrained halation, and light-responsive photographic grain to still images.

The first working vertical slice includes:

- Finder drag-and-drop and Open With support for JPEG, HEIC, PNG, and TIFF
- A compact Instant mode and a separate editing workspace with live preview, zoom, pan, original/effect comparison, and explicit export
- A watched-folder workflow configured in Settings, with stable-file detection and a separate output folder
- Three distinct built-in recipes, persistent user-created recipes with rename/delete management, and detailed per-effect controls
- Seven curated spectral negative-to-print color stocks with a continuously adjustable blend and restrained tonal influence
- Fixed processing order: film tone → spotlight/vignette → diffusion → halation → grain
- Extended-linear Core Image rendering, source metadata preservation, optional GPS stripping, collision-safe filenames, and atomic output writes
- A menu-bar watcher, launch-at-login setting, sandboxed folder bookmarks, and a signed local `.app` bundle

## Run it

The packaged development build is at `dist/Filmify.app`. Double-click it, or run:

```sh
open dist/Filmify.app
```

Filmify currently targets macOS 26 so it can use the native Liquid Glass controls.

## Build and test

```sh
swift test
./Scripts/build-app.sh
```

For a coworker-friendly local build, double-click `Build Filmify.command`.
Requirements and troubleshooting are in [BUILDING.md](BUILDING.md).
Create a clean shareable source ZIP with `./Scripts/package-source.sh`.

The release script compiles the Swift package, builds the icon asset catalog, assembles the app bundle, applies sandbox entitlements, and ad-hoc signs it for local use. Distribution will require a Developer ID signature and notarization.

`AppIcon.icon` is the canonical app-icon source. The build exports both the
modern appearance-aware asset catalog and the flattened Finder fallback from
that package; generated icon renditions are not stored as separate source
assets.

The bundled color-stock cubes are selected from
[ComfyUI-Darkroom](https://github.com/jeremieLouvaert/ComfyUI-Darkroom) and its
MIT-licensed spectral film model. See `Resources/THIRD_PARTY_NOTICES.txt`.
Stock and manufacturer names are descriptive; Filmify's simulations are not
endorsed by or affiliated with their trademark owners.

The product, interaction, imaging, architecture, validation, and delivery rationale is in [docs/PRODUCT_PLAN.md](docs/PRODUCT_PLAN.md).
