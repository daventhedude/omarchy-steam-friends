#!/usr/bin/env node

import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { fileURLToPath } from "node:url"

const testDirectory = path.dirname(fileURLToPath(import.meta.url))
const repository = path.dirname(testDirectory)
const themeHelpersPath = path.join(repository, "Theme.js")
const omarchyRoot = process.env.OMARCHY_PATH || "/usr/share/omarchy"
const themesDirectory = path.join(omarchyRoot, "themes")

function fail(message) {
  process.stderr.write(`FAIL: ${message}\n`)
  process.exit(1)
}

function qmlColor(red, green, blue, alpha = 1) {
  return { r: red, g: green, b: blue, a: alpha }
}

function parseHex(value) {
  const match = String(value || "").match(/^#([0-9a-f]{6})$/i)
  if (!match) fail(`invalid theme color ${value}`)
  const hex = match[1]
  return qmlColor(
    Number.parseInt(hex.slice(0, 2), 16) / 255,
    Number.parseInt(hex.slice(2, 4), 16) / 255,
    Number.parseInt(hex.slice(4, 6), 16) / 255)
}

function parsePalette(file) {
  const values = {}
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    const match = line.match(/^\s*([a-z0-9_]+)\s*=\s*["'](#[0-9a-f]{6})["']/i)
    if (match) values[match[1]] = match[2]
  }
  return values
}

const source = fs.readFileSync(themeHelpersPath, "utf8")
  .replace(/^\.pragma\s+library\s*$/m, "")
const context = vm.createContext({
  Qt: { rgba: qmlColor },
  Math,
  Number,
  isFinite,
})
vm.runInContext(source, context, { filename: themeHelpersPath })

if (!fs.existsSync(themesDirectory)) fail(`Omarchy themes not found at ${themesDirectory}`)

let checkedThemes = 0
for (const directory of fs.readdirSync(themesDirectory).sort()) {
  const colorsFile = path.join(themesDirectory, directory, "colors.toml")
  if (!fs.existsSync(colorsFile)) continue

  const palette = parsePalette(colorsFile)
  if (!palette.foreground || !palette.background || !palette.accent)
    fail(`${directory}: missing foundational colors`)

  const foreground = parseHex(palette.foreground)
  const background = parseHex(palette.background)
  const accent = parseHex(palette.accent)
  const urgent = parseHex(palette.red || palette.color1 || palette.accent)
  const muted = parseHex(palette.muted || palette.color8 || palette.foreground)

  const secondary = context.readableMuted(foreground, background, 4.5)
  const quiet = context.readableMuted(foreground, background, 3.0)
  const accentGraphic = context.ensureContrast(accent, foreground, background, 3.0)
  const accentText = context.ensureContrast(accent, foreground, background, 4.5)
  const urgentGraphic = context.ensureContrast(urgent, foreground, background, 3.0)
  const urgentText = context.ensureContrast(urgent, foreground, background, 4.5)
  const mutedGraphic = context.ensureContrast(muted, quiet, background, 3.0)

  const checks = [
    ["secondary text", secondary, 4.5],
    ["quiet text", quiet, 3.0],
    ["accent graphic", accentGraphic, 3.0],
    ["accent text", accentText, 4.5],
    ["urgent graphic", urgentGraphic, 3.0],
    ["urgent text", urgentText, 4.5],
    ["muted graphic", mutedGraphic, 3.0],
  ]
  for (const [role, color, minimum] of checks) {
    const ratio = context.contrast(color, background)
    if (ratio + 0.002 < minimum)
      fail(`${directory}: ${role} contrast ${ratio.toFixed(2)} < ${minimum}`)
  }

  const badgeText = context.contrastText(accent, foreground, background)
  const bestBadgeRatio = Math.max(
    context.contrast(foreground, accent),
    context.contrast(background, accent))
  if (Math.abs(context.contrast(badgeText, accent) - bestBadgeRatio) > 0.002)
    fail(`${directory}: badge contrast selection is not optimal`)

  checkedThemes++
}

if (checkedThemes < 2) fail("theme matrix did not include both stock palettes")

const uiFiles = [
  "BarWidget.qml",
  "Model.js",
  "Panel.qml",
  "Theme.js",
  ...fs.readdirSync(path.join(repository, "components"))
    .filter(file => file.endsWith(".qml"))
    .map(file => path.join("components", file)),
]

for (const relativeFile of uiFiles) {
  const contents = fs.readFileSync(path.join(repository, relativeFile), "utf8")
  if (/#[0-9a-f]{3,8}\b/i.test(contents))
    fail(`${relativeFile}: fixed UI color bypasses the Omarchy palette`)
  if (/Qt\.(?:darker|lighter)\s*\(/.test(contents))
    fail(`${relativeFile}: one-way lightness transform breaks light themes`)
}

process.stdout.write(`theme contract passed across ${checkedThemes} Omarchy themes\n`)
