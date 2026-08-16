.pragma library

function emptySnapshot() {
  return {
    ok: false,
    configured: false,
    stale: false,
    loading: true,
    error: "",
    warning: "",
    generatedAt: 0,
    self: null,
    friends: [],
    counts: { total: 0, online: 0, inGame: 0 }
  }
}

function safeString(value, maximumLength) {
  var text = typeof value === "string" ? value : ""
  var limit = Math.max(0, Number(maximumLength || 0))
  text = text.replace(/[\u0000-\u001f\u007f]/g, " ")
  text = text.replace(/[\u202a-\u202e\u2066-\u2069]/g, "")
  return limit > 0 && text.length > limit ? text.slice(0, limit) : text
}

function safeInteger(value, minimum, maximum) {
  var number = Number(value)
  if (!isFinite(number)) return minimum
  return Math.max(minimum, Math.min(maximum, Math.floor(number)))
}

function isSteamId(value) {
  return /^[0-9]{17}$/.test(String(value || ""))
}

function safeAvatarUrl(value) {
  var url = safeString(value, 1024)
  var steamStatic = /^https:\/\/(?:[A-Za-z0-9-]+\.)*steamstatic\.com\/[A-Za-z0-9_./%?=&+-]+$/
  var legacyCdn = /^https:\/\/steamcdn-a\.akamaihd\.net\/steamcommunity\/public\/images\/avatars\/[A-Za-z0-9_./%?=&+-]+$/
  return steamStatic.test(url) || legacyCdn.test(url) ? url : ""
}

function sanitizePlayer(player, selfId) {
  if (!player || typeof player !== "object" || !isSteamId(player.steamId)) return null

  var steamId = String(player.steamId)
  var gameId = String(player.gameId || "")
  if (!/^[0-9]{1,12}$/.test(gameId)) gameId = ""

  var country = safeString(player.country, 2).toUpperCase()
  if (!/^[A-Z]{2}$/.test(country)) country = ""

  return {
    steamId: steamId,
    name: safeString(player.name, 128) || "Unknown friend",
    realName: safeString(player.realName, 128),
    profileUrl: "https://steamcommunity.com/profiles/" + steamId + "/",
    avatar: safeAvatarUrl(player.avatar),
    state: safeInteger(player.state, 0, 6),
    stateFlags: safeInteger(player.stateFlags, 0, 2147483647),
    gameName: safeString(player.gameName, 256),
    gameId: gameId,
    lastLogoff: safeInteger(player.lastLogoff, 0, 4102444800),
    friendSince: safeInteger(player.friendSince, 0, 4102444800),
    country: country,
    isSelf: steamId === String(selfId || "")
  }
}

function parseSnapshot(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (!parsed || typeof parsed !== "object" || parsed instanceof Array) return null

    var safe = emptySnapshot()
    safe.ok = parsed.ok === true
    safe.configured = parsed.configured === true
    safe.stale = safe.ok && parsed.stale === true
    safe.loading = false
    safe.error = safeString(parsed.error, 500)
    safe.warning = safeString(parsed.warning, 500)
    safe.generatedAt = safeInteger(parsed.generatedAt, 0, 4102444800)
    var sanitizedSelf = sanitizePlayer(parsed.self, parsed.self ? parsed.self.steamId : "")
    safe.self = sanitizedSelf

    var source = parsed.friends instanceof Array ? parsed.friends : []
    var seen = {}
    for (var i = 0; i < source.length && safe.friends.length < 5000; i++) {
      var friend = sanitizePlayer(source[i], sanitizedSelf ? sanitizedSelf.steamId : "")
      if (!friend || friend.isSelf || seen[friend.steamId]) continue
      seen[friend.steamId] = true
      safe.friends.push(friend)
    }
    safe.counts = countFriends(safe.friends)
    return safe
  } catch (error) {
    return null
  }
}

function countFriends(friends) {
  var online = 0
  var inGame = 0
  var list = friends instanceof Array ? friends : []
  for (var i = 0; i < list.length; i++) {
    if (Number(list[i].state || 0) > 0) online++
    if (String(list[i].gameName || "") !== "") inGame++
  }
  return { total: list.length, online: online, inGame: inGame }
}

function filteredFriends(friends, filter, query, showOffline) {
  var source = friends instanceof Array ? friends : []
  var normalizedQuery = String(query || "").toLowerCase().replace(/^\s+|\s+$/g, "")
  var result = []

  for (var i = 0; i < source.length; i++) {
    var friend = source[i]
    var state = Number(friend.state || 0)
    var gameName = String(friend.gameName || "")

    if (filter === "game" && gameName === "") continue
    if (filter === "online" && state <= 0) continue
    if (filter === "all" && !showOffline && state <= 0) continue

    if (normalizedQuery !== "") {
      var haystack = (String(friend.name || "") + " "
        + String(friend.realName || "") + " " + gameName).toLowerCase()
      if (haystack.indexOf(normalizedQuery) < 0) continue
    }
    result.push(friend)
  }
  return result
}

function initials(name) {
  var clean = String(name || "?").replace(/^\s+|\s+$/g, "")
  if (clean === "") return "?"
  var words = clean.split(/\s+/)
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase()
  return (words[0].charAt(0) + words[words.length - 1].charAt(0)).toUpperCase()
}

function stateLabel(friend) {
  if (!friend) return "Offline"
  if (String(friend.gameName || "") !== "") return "In game"
  switch (Number(friend.state || 0)) {
    case 1: return "Online"
    case 2: return "Busy"
    case 3: return "Away"
    case 4: return "Snooze"
    case 5: return "Looking to trade"
    case 6: return "Looking to play"
    default: return "Offline"
  }
}

function stateColor(friend) {
  if (friend && String(friend.gameName || "") !== "") return "#90ba3c"
  switch (friend ? Number(friend.state || 0) : 0) {
    case 1: return "#66c0f4"
    case 2: return "#f0a35e"
    case 3:
    case 4: return "#b8c4cf"
    case 5:
    case 6: return "#ad8cff"
    default: return "#67707b"
  }
}

function relativeTime(unixSeconds, nowMs) {
  var then = Number(unixSeconds || 0) * 1000
  if (then <= 0) return "Offline"
  var now = Number(nowMs || Date.now())
  var seconds = Math.max(0, Math.floor((now - then) / 1000))
  if (seconds < 60) return "Just now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  return Math.floor(months / 12) + "y ago"
}

function memberSince(unixSeconds) {
  var value = Number(unixSeconds || 0)
  if (value <= 0) return "Steam friend"
  return "Friends since " + new Date(value * 1000).getFullYear()
}

function safeCount(snapshot, key) {
  if (!snapshot || !snapshot.counts) return 0
  var count = Number(snapshot.counts[key] || 0)
  return isFinite(count) ? Math.max(0, Math.floor(count)) : 0
}

function countText(count, singular, plural) {
  return count + " " + (count === 1 ? singular : (plural || singular + "s"))
}
