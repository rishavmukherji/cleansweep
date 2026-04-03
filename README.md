# CleanSweep

A native macOS disk cleanup utility built for developers. Targets the stuff that quietly eats your disk — `node_modules` from old projects, app caches, Docker images, and other dev tool bloat.

Built with SwiftUI. No Xcode required — compiles with just the Command Line Tools.

![CleanSweep screenshot](https://img.shields.io/badge/macOS-14%2B-blue)

## What it does

CleanSweep scans your Mac for common developer disk space hogs and lets you clean them up with a few clicks:

- **node_modules** — finds all `node_modules` directories, shows repo name, size, and last git commit date. Select inactive repos (60+ days) for bulk deletion.
- **Build Artifacts** — `.next/` and `.turbo/` directories across your projects. Rebuild automatically on next `dev`/`build`.
- **Caches** — lists `~/Library/Caches` contents by size. Clear individually or all at once.
- **App & Dev Data** — known space hogs including:
  - App data: Claude VM bundles, WhatsApp media, OrbStack/Docker, Spotify, Telegram
  - Dev tool caches: pnpm store, npm cache, Yarn cache, Homebrew, CocoaPods, Go modules, Cargo registry, pip, Gradle
  - System: Trash, Xcode Derived Data
- **Applications** — lists installed apps sorted by size (info only).

Only items that exist on your machine are shown. Nothing is deleted without explicit confirmation.

## Requirements

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

```bash
git clone https://github.com/rishavmukherji/cleansweep.git
cd cleansweep
chmod +x build.sh
./build.sh
open build/CleanSweep.app
```

On first launch, macOS may block the app since it's ad-hoc signed. Right-click the app → **Open** to bypass Gatekeeper.

## Install to Applications

```bash
cp -R build/CleanSweep.app /Applications/
```

## Project structure

```
Sources/
  App.swift        — App entry point
  Scanner.swift    — Disk scanning logic and data models
  Views.swift      — All SwiftUI views
Info.plist         — App bundle metadata
build.sh           — Compile, bundle, and sign
```
