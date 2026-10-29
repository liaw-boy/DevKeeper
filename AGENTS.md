# AGENTS.md

Detailed architecture notes (in Traditional Chinese) live in `CLAUDE.md`; read it before non-trivial changes.

## Commands
- `swift build` / `swift test` / `swift test --filter PythonLogicTests/testName` (tests only cover `DevKeeperCore`).
- `swift run DevKeeper` runs the macOS app (no bundle, so version falls back). `swift run devkeeper-cli scan|python list|audit|fix|serve`.
- `./bundle.sh` builds the release app, icon, Info.plist and DMG. Version is hardcoded there (`VERSION`/`BUILD`); no plist in the repo.
- No linter. CI runs build, test and a CLI smoke test on macOS and Linux. `audit` exits 1 when vulnerabilities are found.
- `DevKeeper.app`, `DevKeeper.dmg` and `.build` are artifacts. Don't edit them.

## Structure
- `Sources/DevKeeperCore`: Foundation-only logic shared by the app and CLI, and it must also build on Linux. Use `#if os(...)` for platform differences. Types and methods used elsewhere must be `public`.
- Put audit, fix and interpreter-selection logic in `Engine/Engines.swift` so the app and CLI behave the same, and add tests in `Tests/DevKeeperCoreTests`.
- `Sources/DevKeeper`: SwiftUI app, macOS only. A single `AppViewModel` coordinates all state and operations. A new page needs a `NavigationTab` case (defined in `AppViewModel.swift`) and a matching `MainView` change.
- `Sources/devkeeper-cli/main.swift`: hand-rolled argument parsing, no ArgumentParser. No external dependencies anywhere.
- `devkeeper-cli serve` is a read-only, loopback-only web UI (`Core/Web`). Re-evaluate `RequestGuard` before adding any endpoint that modifies the system.

## Gotchas
- Never execute `/usr/bin/python3` when the Xcode command line tools are missing, because it triggers a system install dialog.
- PEP 668 (`EXTERNALLY-MANAGED`) interpreters are read-only. Never run pip writes against them.
- `ShellExecutor.run` treats a nonzero exit with non-empty stdout as success (`npm list` behavior).
- Verify fixes by checking the installed version, not the exit status.
- For uv tool environments, upgrade a single package with `uv pip install --python`, not `uv tool upgrade`.
- UI text is Traditional Chinese. No emoji; use SF Symbols only.

## UI
- Follow `DESIGN.md`. Use only the `DK` tokens and components in `Sources/DevKeeper/Design/`: no hardcoded colours or font sizes, no native `Menu`/`Picker`/`Toggle`/`confirmationDialog`/`ProgressView`/`.sheet`/`.help`.
- Check components visually with `DEVKEEPER_GALLERY=1 .build/debug/DevKeeper` (light and dark side by side).
