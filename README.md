# CleanSweep

A native macOS disk cleanup utility built for developers. Targets the stuff that quietly eats your disk — `node_modules` from old projects, build artifacts, app caches, Docker images, and other dev tool bloat.

Built with SwiftUI. No Xcode required — compiles with just the Command Line Tools.

## What it does

CleanSweep scans your Mac for common developer disk space hogs and lets you clean them up with a few clicks:

- **node_modules** — finds all `node_modules` directories, shows repo name, size, and last git commit date. Select inactive repos (60+ days) for bulk deletion.
- **Build Artifacts** — `.next/` and `.turbo/` directories across your projects. Rebuild automatically on next `dev`/`build`.
- **Caches** — lists `~/Library/Caches` contents by size. Clear individually or all at once.
- **App & Dev Data** — known space hogs including:
  - App data: Claude VM bundles, WhatsApp media, OrbStack/Docker, Spotify, Telegram
  - Dev tool caches: pnpm store, npm cache, Yarn cache, Homebrew, CocoaPods, Go modules, Cargo registry, pip, Gradle
  - System: Trash, Xcode Derived Data
  - Click any item to drill into its contents and selectively delete individual files/folders
  - Smart attribution for select drill-downs:
    - **pnpm Store** — maps each store version (v3/v10/v11) to the repos referencing it; flags orphaned versions as "Unreferenced — safe to clear"
    - **Claude VM Bundles** — breaks the bundle into `rootfs.img`, `rootfs.img.zst`, `sessiondata.img` with per-file impact notes; reassures that chat history is unaffected; warns when a file is held open by the live VM (deletion succeeds but space reclaim is deferred until the VM shuts down)
    - **OrbStack / Docker** — when the daemon is running, lists individual images, containers, volumes, and the build cache with their compose-project label, and uses the right `docker rmi` / `rm` / `volume rm` / `builder prune` command per row; offers a Start OrbStack button when stopped
- **Applications** — lists installed apps sorted by size (info only).

Only items that exist on your machine are shown. Nothing is deleted without explicit confirmation.

## Requirements

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Install

```bash
git clone https://github.com/rishavmukherji/cleansweep.git
cd cleansweep
chmod +x build.sh
./build.sh
```

This compiles the app, installs it to `/Applications`, and clears the quarantine flag. Launch it from Spotlight, Launchpad, or:

```bash
open /Applications/CleanSweep.app
```

## Project structure

```
Sources/
  App.swift           — App entry point
  Scanner.swift       — Disk scanning logic and data models
  Views.swift         — All SwiftUI views
CleanSweep.icns       — App icon
Info.plist            — App bundle metadata
build.sh              — Compile, bundle, sign, and install
```

## License

MIT
