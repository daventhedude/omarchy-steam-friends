# Changelog

All notable changes are documented here. Versions follow semantic versioning.

## 1.0.1 — 2026-08-17

### Added

- Read-only GitHub CI for portable syntax, security, model, manifest, whitespace, and demo-data contracts.
- Privacy-safe issue forms, a trust-boundary pull-request checklist, and contribution guidance.
- Reproducible release archive and checksum publication.
- Native Qt 6 keyboard-event and portable UI-wiring contracts.

### Changed

- Initial loading, Steam startup, completion, and failure states now provide immediate theme-native feedback.
- Panel focus is restored after asynchronous refreshes and Enter in search activates the selected match consistently.
- Escape now clears and exits search in one step before the next Escape closes the panel.

### Fixed

- Steam URI actions are serialized in both QML and the helper, preventing repeated Enter/click input from launching competing Steam clients during a cold start.
- Steam readiness now requires a live process and command pipe, while private timestamp-only guard state survives a shell reload without retaining friend IDs.

## 1.0.0 — 2026-08-17

### Added

- Theme-native Omarchy Quattro Steam friends bar widget and keyboard-accessible panel.
- Live presence, game activity, search, native Steam actions, and the data-driven Presence Orbit.
- Secure local Web API setup, strict response normalization, account-bound cache, and dual shell/QML validation.
- Contracts covering security boundaries, the QML model, 5,000-friend batching, and all installed Omarchy themes.
