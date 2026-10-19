<div align="center">

<p align="center">
  <strong>English</strong> ·
  <a href="README_TR.md">Türkçe</a> ·
  <a href="README_JA.md">日本語</a> ·
  <a href="README_ZH.md">简体中文</a> ·
  <a href="README_ES.md">Español</a>
</p>

<img src="assets/icon.png" width="128" height="128" alt="EXdl icon">

# EXdl
### External Download & Install Manager for macOS

**Install Mac apps straight onto an external drive while keeping them in Launchpad and Spotlight.**

<br>

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple&logoColor=white)](#requirements)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-0A84FF?style=flat-square)](#requirements)
[![Release](https://img.shields.io/badge/Release-v1.1.0-blue?style=flat-square)](https://github.com/erdembeler/exdl/releases/latest)
[![Notarized](https://img.shields.io/badge/Apple-notarized-34C759?style=flat-square)](#install)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white)](Package.swift)
[![MIT License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)

[**Download Latest Release**](https://github.com/erdembeler/exdl/releases/latest) &nbsp;·&nbsp; [How it works](#how-it-works) &nbsp;·&nbsp; [Permissions](#permissions-explained) &nbsp;·&nbsp; [Build from source](#build-from-source)

</div>

<br>

EXdl is a lightweight native macOS menu bar application designed to make external SSDs a seamless, first-class home for your applications without sacrificing system integration.

---

## The Problem

Mac internal SSDs cannot be upgraded after purchase, and large applications—such as developer suites, 3D editors, game engines, and games—quickly fill internal storage.

When you download an app via a `.dmg` file, macOS provides a drag-and-drop window that only allows copying to `/Applications` on the internal disk. If you manually drag the app to an external drive and create an alias or POSIX symbolic link:
- macOS Launchpad, Spotlight, and the new macOS Sequoia Applications view often fail to index symlinks properly.
- If you disconnect the external drive and click a broken symlink, the app fails silently or throws confusing errors.
- Whenever an app performs an automatic update, the updater overwrites the link with a full copy on the internal SSD, silently consuming internal storage again.

---

## How EXdl Works

<p align="center">
  <img src="assets/how-it-works.svg" width="720" alt="EXdl installation and smart launcher workflow">
</p>

EXdl does not rely on fragile symlinks. Instead, it uses **Smart App Stubs**:
1. When you mount a disk image (`.dmg`), EXdl detects it and presents a native installation window targeting your external SSD.
2. The complete application bundle lives on your external drive.
3. In `/Applications`, EXdl creates a lightweight (~500 KB) native launcher stub that inherits the application's original icon, metadata, and bundle identifier.
4. Launchpad, Spotlight, and the Dock recognize the app as a genuine installed application.
5. If the drive is disconnected when you click the app, EXdl displays a clear dialog asking you to reconnect the drive, rather than crashing or failing silently.

---

## Features

- **Automatic Disk Image Detection** — Detects mounted `.dmg` images automatically, prompts you to install directly to your external drive, and unmounts the disk image once installation completes.
- **Update Protection** — If an in-app updater overwrites the launcher with a full internal copy, EXdl detects the change and offers to move the update back to your external drive automatically.
- **Storage Dashboard & Migration** — View your internal and external drive usage in one place. Move existing apps from internal storage to your external drive with a single click, or restore them back whenever needed.
- **Incompatible Application Filtering** — Certain applications fail if moved off the boot disk. EXdl automatically protects apps like Xcode, developer toolchains, Apple system tools, apps with macOS System Extensions, and background launch daemons by keeping them internal.
- **10 Customizable Menu Bar Icons** — Choose from 10 Retina vector template icons in Settings (defaulting to the EX Monogram). Icons render filled when monitoring is active and hollow/outlined when paused.
- **Native In-App Software Updates (OTA)** — Built-in updater checks GitHub Releases, downloads verified Apple Developer ID signed updates, and updates the app seamlessly in place.
- **Privacy & Lightweight** — Runs quietly in the menu bar, supports launch at login, consumes minimal resources, and makes no network requests other than user-controlled update checks.

---

## Comparison

| Feature | Standard macOS | Manual Symlinks | With EXdl |
| :-- | :-- | :-- | :-- |
| **DMG Installation Target** | Internal `/Applications` only | Manual drag and drop | Direct 1-click external install |
| **Launchpad & Spotlight** | Supported | Frequently broken | Fully supported |
| **Drive Disconnected** | N/A | Silent failure / error | Helpful reconnection prompt |
| **App Auto-Updates** | Keeps on internal disk | Overwrites and breaks symlink | Automatically restored to external SSD |
| **Internal SSD Space Saved** | 0 GB | High, but fragile | Full savings, stable and native |

---

## Permissions Explained

macOS requires specific privacy permissions for EXdl to operate properly:

1. **App Management (`kTCCServiceSystemPolicyAppBundles`) — Required**
   - **Why it is needed:** EXdl needs permission to create and update the lightweight launcher stubs inside `/Applications` and move application bundles to your external SSD.
   - **How to grant:** Open *System Settings → Privacy & Security → App Management* and enable EXdl. If EXdl is not listed yet, click the `+` button and add it from `/Applications`.
2. **Full Disk Access — Recommended**
   - **Why it is needed:** Allows EXdl to read downloaded disk images from `~/Downloads` and write to external volumes without triggering repetitive macOS permission prompts for each folder.
   - **How to grant:** Open *System Settings → Privacy & Security → Full Disk Access* and enable EXdl.

---

## Installation

1. Download the latest release from the [GitHub Releases](https://github.com/erdembeler/exdl/releases/latest) page (`EXdl-1.1.0.dmg` or `EXdl-1.1.0.zip`).
2. Open the disk image and drag **EXdl** into **Applications**.
3. Launch EXdl. The Setup Assistant will guide you through language selection, target drive configuration, and required permissions.
4. Once completed, EXdl lives unobtrusively in your macOS menu bar.

All release binaries are signed with an Apple Developer ID certificate and notarized by Apple.

---

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 / M2 / M3 / M4)
- External storage formatted as **APFS** (recommended) or **Mac OS Extended (Journaled)**

---

## Building from Source

```bash
git clone https://github.com/erdembeler/exdl.git
cd exdl

# Build the application bundle
./build_app.sh

# Build DMG and ZIP distribution archives
./package_release.sh
```

---

## License

This project is licensed under the [MIT License](LICENSE).
