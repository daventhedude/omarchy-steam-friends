#!/usr/bin/env node

import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { fileURLToPath } from "node:url"

const testDirectory = path.dirname(fileURLToPath(import.meta.url))
const repository = path.dirname(testDirectory)
const modelPath = path.join(repository, "Model.js")

function fail(message) {
  process.stderr.write(`FAIL: ${message}\n`)
  process.exit(1)
}

function assert(condition, message) {
  if (!condition) fail(message)
}

const source = fs.readFileSync(modelPath, "utf8")
  .replace(/^\.pragma\s+library\s*$/m, "")
const context = vm.createContext({})
vm.runInContext(source, context, { filename: modelPath })

assert(context.parseSnapshot("") === null, "empty input was accepted")
assert(context.parseSnapshot("[]") === null, "array root was accepted")
assert(context.parseSnapshot("{broken") === null, "invalid JSON was accepted")

const selfId = "00000000000000000"
const friendId = "00000000000000001"
const raw = JSON.stringify({
  ok: true,
  configured: true,
  stale: true,
  error: "bad\nerror\u202e",
  warning: "warn\u0000ing",
  generatedAt: 999999999999,
  self: {
    steamId: selfId,
    name: "Orbit",
    profileUrl: "file:///etc/passwd",
    avatar: "https://avatars.fastly.steamstatic.com/safe_full.jpg",
    state: 1,
  },
  friends: [
    {
      steamId: friendId,
      name: "Bad\nName\u202e",
      realName: "R".repeat(140),
      profileUrl: "file:///etc/shadow",
      avatar: "file:///etc/shadow",
      state: 999,
      stateFlags: -1,
      gameName: "Game\u0000Name",
      gameId: "../../run",
      lastLogoff: -10,
      friendSince: 999999999999,
      country: "de",
    },
    { steamId: friendId, name: "Duplicate", state: 1 },
    { steamId: selfId, name: "Injected self", state: 1 },
    { steamId: "not-a-steam-id", name: "Invalid", state: 1 },
  ],
  counts: { total: 999, online: 999, inGame: 999 },
})

const safe = context.parseSnapshot(raw)
assert(safe && safe.ok && safe.configured && safe.stale, "valid snapshot flags were lost")
assert(safe.error === "bad error", "error control/Bidi characters survived")
assert(safe.warning === "warn ing", "warning control characters survived")
assert(safe.generatedAt === 4102444800, "timestamp was not bounded")
assert(safe.self && safe.self.isSelf, "self identity was not reconstructed")
assert(safe.self.profileUrl === `https://steamcommunity.com/profiles/${selfId}/`, "self profile URL was trusted")
assert(safe.friends.length === 1, "invalid, duplicate, or self entries survived")

const friend = safe.friends[0]
assert(friend.name === "Bad Name", "friend control/Bidi characters survived")
assert(friend.realName.length === 128, "friend text length was not bounded")
assert(friend.profileUrl === `https://steamcommunity.com/profiles/${friendId}/`, "friend profile URL was trusted")
assert(friend.avatar === "", "non-Steam avatar URL survived")
assert(friend.state === 6 && friend.stateFlags === 0, "presence integers were not bounded")
assert(friend.gameName === "Game Name" && friend.gameId === "", "game fields were not sanitized")
assert(friend.lastLogoff === 0 && friend.friendSince === 4102444800, "friend timestamps were not bounded")
assert(friend.country === "DE", "country code was not normalized")
assert(
  safe.counts.total === 1 && safe.counts.online === 1 && safe.counts.inGame === 1,
  `untrusted counts were used: ${JSON.stringify(safe.counts)}`)

assert(context.safeAvatarUrl("https://cdn.akamai.steamstatic.com/a/b.png") !== "", "valid Steam CDN URL was rejected")
assert(context.safeAvatarUrl("https://steamstatic.com@127.0.0.1/private") === "", "URL userinfo bypass was accepted")
assert(context.safeAvatarUrl("http://avatars.steamstatic.com/a.png") === "", "non-HTTPS avatar was accepted")
assert(context.safeAvatarUrl("data:image/svg+xml,boom") === "", "data URL avatar was accepted")

const palette = { playing: "play", online: "on", busy: "busy", away: "away", social: "social", offline: "off" }
assert(context.stateColor({ gameName: "Game", state: 1 }, palette) === "play", "playing color mapping failed")
assert(context.stateColor({ gameName: "", state: 2 }, palette) === "busy", "busy color mapping failed")
assert(context.stateColor({ gameName: "", state: 6 }, palette) === "social", "social color mapping failed")
assert(context.stateColor({ gameName: "", state: 0 }, palette) === "off", "offline color mapping failed")

const oversizedFriends = []
for (let index = 1; index <= 5002; index++) {
  oversizedFriends.push({
    steamId: String(index).padStart(17, "0"),
    name: `Friend ${index}`,
    state: 1,
  })
}
const bounded = context.parseSnapshot(JSON.stringify({
  ok: true,
  configured: true,
  friends: oversizedFriends,
}))
assert(bounded && bounded.friends.length === 5000, "friend collection was not bounded")
assert(bounded.counts.total === 5000 && bounded.counts.online === 5000, "bounded collection counts drifted")

process.stdout.write("model contract passed\n")
