## Summary

Describe the user-visible change and why it belongs in Steam Friends.

## Trust-boundary impact

List any new endpoint, executable, stored field, permission, URI action, or untrusted input. Write `None` if unchanged.

## Validation

- [ ] `bash -n scripts/steam-friends tests/security.sh`
- [ ] `./tests/security.sh`
- [ ] `./tests/model-contract.mjs`
- [ ] `./tests/ui-contract.mjs`
- [ ] `./tests/theme-contract.mjs` on Omarchy
- [ ] Qt 6 `tests/tst_keyboard.qml` on Omarchy
- [ ] `omarchy plugin validate .` on Omarchy
- [ ] `qmllint -I /usr/share/omarchy/shell …` on Omarchy
- [ ] I used only fixtures or sanitized data and committed no credentials or private Steam data.
