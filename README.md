# CleanSweep

A native macOS disk cleanup utility built with SwiftUI. No Xcode required — compiles with just the Command Line Tools.

![CleanSweep screenshot](https://img.shields.io/badge/macOS-14%2B-blue)

## What it does

CleanSweep scans your Mac for common disk space hogs and lets you clean them up with a few clicks:

- **node_modules** — finds all `node_modules` directories, shows repo name, size, and last git commit date. Select inactive repos (60+ days) for bulk deletion.
- **Caches** — lists `~/Library/Caches` contents by size. Clear individually or all at once.
- **App Data** — known space hogs like Claude VM bundles, WhatsApp media, OrbStack/Docker, Spotify cache, Telegram cache.
- **Applications** — lists installed apps sorted by size (info only).

Nothing is deleted without explicit confirmation.

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
