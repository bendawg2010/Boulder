# Boulder — Windows (Tauri build)

The Windows port of [Boulder](https://github.com/bendawg2010/Boulder),
the chill productivity app from the macOS side of the repo.

Same brand. Same algorithm. System tray icon, focus timer, dense
boulder silhouette, growing one grain per 5 focused minutes.

This is a **scaffold** — the Mac build is the canonical app and ships
today. The Windows build is wired up but unsigned/unreleased. If you
want to be a Windows beta tester, drop a note on the
[waitlist issue](https://github.com/bendawg2010/Boulder/issues/new?title=Windows%20beta%20waitlist).

## Stack

- **Tauri 2.x** — Rust shell + WebView2 frontend
- **TypeScript + plain HTML/CSS** — no framework, same look as the website
- **`tauri-plugin-store`** — persisted state at `%APPDATA%/Boulder/state.json`
- **`tauri-plugin-tray`** — Windows system-tray icon (matches the macOS menubar)

The rock-rendering algorithm is the same dense-silhouette canvas
code that powers the share page on `boulder-43p.pages.dev/r/`.

## Build (on a Windows machine)

```pwsh
# One-time: Rust toolchain + WebView2 (Win11 has it pre-installed)
rustup toolchain install stable
cargo install tauri-cli

# Dev — opens the tray app with hot-reload on src/*.ts
cd src-tauri
cargo tauri dev

# Release — produces target/release/bundle/msi/Boulder_*.msi
cargo tauri build
```

The Mac dev environment can't build a Windows `.msi`. Cross-build
attempts via Wine/`wineconsole` aren't reliable enough to ship from.

## Structure

```
windows-app/
├── README.md                 ← you are here
├── package.json              ← npm scripts
├── src/                      ← web frontend (loaded by the Rust shell)
│   ├── index.html
│   ├── styles.css
│   └── main.ts               ← focus session, persistence, render loop
└── src-tauri/
    ├── Cargo.toml
    ├── tauri.conf.json
    └── src/main.rs           ← system tray, window, persistence wire-up
```

## TODO (for the actual beta)

- [ ] Implement focus-blocker (Windows-side: `EnumProcesses` + `TerminateProcess`)
- [ ] Cloud sync (depends on the v1.8 Supabase backend)
- [ ] Sparkle-equivalent auto-update (Tauri has a built-in updater plugin)
- [ ] Code-sign the MSI (Authenticode certs — about $200/yr — vs. unsigned + SmartScreen warning)
- [ ] Windows widgets API (Win11 only — likely v1.9)

## License

Same as the parent: MIT.
