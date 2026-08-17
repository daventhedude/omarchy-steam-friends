#!/usr/bin/env node

import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, resolve } from "node:path"

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const panel = readFileSync(resolve(root, "Panel.qml"), "utf8")
const backend = readFileSync(resolve(root, "scripts/steam-friends"), "utf8")

function contains(source, fragment, message) {
  assert.ok(source.includes(fragment), message)
}

contains(panel,
  "onActivateRequested: root.activateCurrent()",
  "Panel Enter/Space activation must route through the state-aware action")
contains(panel,
  "onAccepted: {\n            root.activateCurrent()",
  "Search Enter must activate the selected result before restoring panel focus")
contains(panel,
  "if (steamActionProc.running)",
  "QML must reject duplicate Steam actions while the helper is active")
contains(panel,
  "steamActionProc.command = [backendPath, \"steam-action\"].concat(actionArguments)",
  "Steam actions must use the validating helper instead of direct URI execution")
contains(panel,
  "[\"chat\", String(friend.steamId)]",
  "Chat activation must pass only the validated Steam ID to the helper")
contains(panel,
  "sourceComponent: !root.initialized\n          ? loadingView",
  "The first snapshot must have an explicit loading state")
contains(panel,
  "root.restorePanelFocus()",
  "Panel focus must be restored after asynchronous state transitions")

assert.doesNotMatch(panel,
  /execDetached\(\[\s*["']xdg-open["']\s*,\s*["']steam:/,
  "QML must not bypass the serialized Steam action helper")

contains(backend,
  "pgrep -u \"$EUID\" -x steam",
  "A stale command pipe alone must not count as a ready Steam client")
contains(backend,
  "elif steam_process_running; then",
  "A slow live Steam startup must never be treated as permission to relaunch")
contains(backend,
  "flock -n \"$output_fd\"",
  "Steam actions must be serialized across helper processes")
contains(backend,
  "write_action_guard \"$((now + 45))\"",
  "Cold starts must retain a crash-prevention guard")
contains(backend,
  "uri=\"steam://friends/message/${steam_id}\"",
  "The helper must reconstruct chat URIs after Steam ID validation")

console.log("UI contracts passed")
