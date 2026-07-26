# Congmiao Toolbox

Congmiao Toolbox is a local desktop toolbox built with Tauri 2, Svelte 5, and Bun.

> **flutter 分支说明**：本分支包含 Flutter 版移植，位于 [`flutter_app/`](flutter_app/README.md)；
> 原 Tauri/Svelte 代码保持不动作为对照参考。架构分析与移植映射见
> [`docs/flutter-port.md`](docs/flutter-port.md)。

## Features

- Desktop utility hub with multiple local tools in a single window
- Peek PC LAN monitoring with a single high-entropy API key, failed-auth throttling, connection logs, and a mobile dashboard
- Screen time tracking
- Heart rate overlay / widget support
- In-app updater and launch-at-login support
- Persistent desktop workspace, window layout, todos, timers, and wallpaper
- Safe file tools for previewable batch rename, rule-based organization, undo, and read-only duplicate scanning
- System tray, global quick-search shortcut, timer notifications, and lazy-loaded tool windows
- Quick launcher with fuzzy search, safe commands, calculations, URLs, favorites, recent tools, and reusable workspace templates

## Stack

- Tauri 2
- Svelte 5
- TypeScript
- Bun
- Rust

## Local Development

```bash
bun install
bun run tauri:dev
```

## Production Build

```bash
bun run tauri:build
```

## Validation

```bash
bun run check
bun run test
cd src-tauri && cargo test --all-targets
```

## Release Workflow

Version releases are published from GitHub Actions when you push a tag in the form `v*`.

Prepare the version locally, commit it, and then create the matching tag:

```bash
bun run version:sync 0.2.9
git add package.json src-tauri/Cargo.toml src-tauri/Cargo.lock src-tauri/tauri.conf.json
git commit -m "chore: release v0.2.9"
git tag v0.2.9
git push origin main v0.2.9
```

The release workflow also synchronizes the build version from the tag as a final safeguard, so a
tagged build cannot accidentally publish updater artifacts with an older application version.

The current workflow publishes:

- macOS build
- Windows NSIS `.exe` build

Windows MSI is intentionally disabled.

## Updater Secrets

The updater workflow requires these GitHub repository secrets:

- `TAURI_SIGNING_PRIVATE_KEY`
- `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`

Generate the updater signing key locally on your own machine, then copy the key content and password into the GitHub repository secrets above.

```bash
bunx tauri signer generate -w ~/.tauri/congmiao-toolbox.key
```

Keep the generated private key in a password manager and an offline backup. Copy its public key
into `plugins.updater.pubkey` in `src-tauri/tauri.conf.json`. Existing installations trust that
exact public key, so losing or replacing the private key prevents them from accepting future
updates.

After a tagged release finishes, the workflow validates that `latest.json` has the same version as
the tag and contains signed download entries for Windows x64, macOS Apple Silicon, and macOS Intel.

Do not commit the private key, password file, or any machine-specific local path into this repository.
