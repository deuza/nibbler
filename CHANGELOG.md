# Changelog

All notable changes to this fork of Nibbler will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- README: what gpg's warning about an uncertified key means when verifying a release, and how to certify the key locally.

## [3.0.0] - 2026-11-24

First release of this fork, with its own version numbers from now on. It is based on the official Nibbler (rooklift/nibbler) as of commit 772a023, whose last release is 2.5.8; every change listed here is relative to that release.

### Changed

- **Breaking:** built with Electron 44.11.5 (Chromium 152, Node.js 24) instead of Electron 9.4.4, which has been out of support since March 2021. Nibbler now needs a 64-bit system, Windows 10 or later, or macOS 13 (Ventura) or later.
- The Linux release is a `.tar.gz` archive instead of a `.zip`, so that the executable files keep their permissions.
- `install.sh` (Linux) and `install_mac.sh` (macOS) install this fork. The macOS application identifier is `com.deuza.nibbler`.
- Links to the project point to this repository.

### Added

- Optional evaluation bar next to the board (Display > Evaluation bar).
- Optional board coordinates (Display > Coordinates).
- Optional `[%eval]` command in saved PGN files, read back when the file is opened (File > PGN saved statistics).
- Optional reload of the last opening book at startup (Play > Reload book at startup).
- Several Syzygy folders can be selected at once (also merged upstream).
- `files/scripts/release.sh`, which builds the release archives in a reproducible way, together with their `SHA256SUMS`.
- This changelog, and a French README (`README.fr.md`).

### Fixed

- Black move numbers after a variation or a comment in exported PGN (upstream issue #100).
- Statistics missing from exported PGN for moves the engine never reported (upstream issue #274).
- "Object has been destroyed" error on quit (also merged upstream).
- `builder.py` keeps the Unix permissions of the Electron archive, so the Linux binary is executable.
- Fixes made upstream since 2.5.8: clipboard with recent Electron versions, UCI check options sent as lowercase `true` / `false`, more text from engines and files escaped before display, online position lookups cached without move numbers, graph redrawn only when needed, and several robustness fixes.
