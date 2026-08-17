# Contributing

Steam Friends welcomes focused fixes and improvements that preserve its native Omarchy feel, local-first data flow, and small trust surface.

## Before changing code

- Never use or commit a real Steam Web API key, Steam ID, friend name, profile response, or private snapshot. Use the built-in demo fixture and synthetic 17-digit IDs.
- Keep the API key out of URLs, process arguments, QML, logs, caches, tests, and screenshots.
- Do not add endpoints, redirect following, executable discovery, privileges, install hooks, or persistent fields without documenting and testing the new trust boundary.
- Render remote text as plain text. Reconstruct actionable URLs from validated identifiers instead of trusting response URLs.
- Use Omarchy semantic colors and `Style` tokens. Do not add fixed palette colors that break light, monochrome, or custom themes.

## Local checks

Run the portable contracts everywhere:

```bash
bash -n scripts/steam-friends tests/security.sh
./tests/security.sh
./tests/model-contract.mjs
./tests/ui-contract.mjs
./scripts/steam-friends demo | jq .
```

On an Omarchy system, also run the native gates:

```bash
./tests/theme-contract.mjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_keyboard.qml
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml components/*.qml
```

Use `"_demoMode": true` only in your local widget settings for visual testing. Remove it before taking a production-state screenshot or handing off a change.

## Pull requests

Keep each pull request scoped to one coherent change. Explain user impact and every trust-boundary change, update the relevant documentation, and add a regression test. Public bug reports and pull requests must not contain credentials or private Steam data; use GitHub private vulnerability reporting for exploitable findings.
