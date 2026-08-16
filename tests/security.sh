#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${REPO_ROOT}/scripts/steam-friends"
AUDIT_TMP="$(mktemp -d)"
TEST_HOME="${AUDIT_TMP}/home"
TEST_CONFIG="${AUDIT_TMP}/config"
TEST_CACHE="${AUDIT_TMP}/cache"
TEST_BIN="${AUDIT_TMP}/bin"
FAKE_CURL_LOG="${AUDIT_TMP}/curl.log"
TEST_KEY="$(printf '0%.0s' {1..32})"
TEST_SELF_ID="00000000000000000"
TEST_FRIEND_ONE="00000000000000001"
TEST_FRIEND_TWO="00000000000000002"

cleanup() {
  if [[ -n "$AUDIT_TMP" && -d "$AUDIT_TMP" && -O "$AUDIT_TMP" ]]; then
    find "$AUDIT_TMP" -xdev -depth -delete
  fi
}

trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_jq() {
  local expression="$1"
  local json="$2"
  jq -e "$expression" <<<"$json" >/dev/null || fail "jq assertion: ${expression}"
}

write_config() {
  mkdir -p "${TEST_CONFIG}/omarchy"
  jq -cn --arg apiKey "$TEST_KEY" --arg steamId "$TEST_SELF_ID" \
    '{apiKey: $apiKey, steamId: $steamId}' \
    >"${TEST_CONFIG}/omarchy/steam-friends.json"
  chmod 600 "${TEST_CONFIG}/omarchy/steam-friends.json"
}

run_snapshot() {
  env \
    HOME="$TEST_HOME" \
    XDG_CONFIG_HOME="$TEST_CONFIG" \
    XDG_CACHE_HOME="$TEST_CACHE" \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    FAKE_CURL_LOG="$FAKE_CURL_LOG" \
    EXPECTED_KEY="$TEST_KEY" \
    FAKE_STEAM_MODE="${FAKE_STEAM_MODE:-normal}" \
    "$BACKEND" snapshot
}

mkdir -p "$TEST_HOME" "$TEST_BIN"

cat >"${TEST_BIN}/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

arguments=" $* "
[[ "$arguments" == *" --disable "* ]] || exit 90
[[ "$arguments" == *" --proto =https "* ]] || exit 91
[[ "$arguments" == *" --tlsv1.2 "* ]] || exit 92
[[ "$arguments" == *" --max-filesize 2097152 "* ]] || exit 93

config="$(</dev/stdin)"
[[ "$config" == *"header = \"x-webapi-key: ${EXPECTED_KEY}\""* ]] || exit 94
[[ "$config" != *'data-urlencode = "key='* ]] || exit 95
printf 'ARGS%s\n%s\n' "$arguments" "$config" >>"$FAKE_CURL_LOG"

if [[ "$FAKE_STEAM_MODE" == "network-failure" ]]; then
  exit 22
fi

if [[ "$config" == *'/GetFriendList/v1/'* ]]; then
  if [[ "$FAKE_STEAM_MODE" == "invalid-friend-id" ]]; then
    printf '%s\n' '{"friendslist":{"friends":[{"steamid":"not-a-steamid","friend_since":1700000000}]}}'
  else
    printf '%s\n' '{"friendslist":{"friends":[{"steamid":"00000000000000001","friend_since":1700000000},{"steamid":"00000000000000002","friend_since":1710000000}]}}'
  fi
  exit 0
fi

if [[ "$config" == *'/GetPlayerSummaries/v2/'* ]]; then
  printf '%s\n' '{"response":{"players":[
    {"steamid":"00000000000000000","personaname":"Orbit","profileurl":"file:///etc/passwd","avatarfull":"https://avatars.fastly.steamstatic.com/abc_full.jpg","personastate":1,"personastateflags":0,"lastlogoff":1786871000,"loccountrycode":"de"},
    {"steamid":"00000000000000001","personaname":"Bad\nName","profileurl":"file:///etc/shadow","avatarfull":"file:///etc/shadow","personastate":1,"personastateflags":0,"gameextrainfo":"Counter-Strike 2","gameid":"730","lastlogoff":1786871000,"loccountrycode":"US"},
    {"steamid":"00000000000000002","personaname":"SynthRider","profileurl":"custom://unexpected","avatarfull":"https://steamcdn-a.akamaihd.net/steamcommunity/public/images/avatars/00/demo_full.jpg","personastate":3,"personastateflags":0,"lastlogoff":1786871000},
    {"steamid":"00000000000000009","personaname":"Unrequested","avatarfull":"https://example.com/avatar.jpg","personastate":1}
  ]}}'
  exit 0
fi

exit 96
FAKE_CURL
chmod 700 "${TEST_BIN}/curl"

# Unconfigured startup is deterministic and does not contact Steam.
unconfigured="$(run_snapshot)"
assert_jq '.configured == false and .ok == false and (.friends | length == 0)' "$unconfigured"
[[ ! -e "$FAKE_CURL_LOG" ]] || fail 'unconfigured snapshot contacted curl'

# A valid private config produces a bounded, normalized snapshot.
write_config
snapshot="$(run_snapshot)"
assert_jq '.ok and .configured and (.friends | length == 2)' "$snapshot"
assert_jq '.counts == {"total":2,"online":2,"inGame":1}' "$snapshot"
assert_jq '.self.profileUrl == "https://steamcommunity.com/profiles/00000000000000000/"' "$snapshot"
assert_jq '.self.avatar == "https://avatars.fastly.steamstatic.com/abc_full.jpg"' "$snapshot"
assert_jq '.friends[0].name == "Bad Name"' "$snapshot"
assert_jq '.friends[0].avatar == ""' "$snapshot"
assert_jq '.friends[0].profileUrl == "https://steamcommunity.com/profiles/00000000000000001/"' "$snapshot"
assert_jq '.friends[1].avatar | startswith("https://steamcdn-a.akamaihd.net/")' "$snapshot"
assert_jq 'all(.friends[]; .steamId != "00000000000000009")' "$snapshot"
[[ "$snapshot" != *"$TEST_KEY"* ]] || fail 'snapshot contains the API key'
[[ "$(stat -c '%a' "${TEST_CACHE}/omarchy-steam-friends")" == "700" ]] || fail 'cache directory mode is not 0700'
[[ "$(stat -c '%a' "${TEST_CACHE}/omarchy-steam-friends/snapshot.json")" == "600" ]] || fail 'cache file mode is not 0600'
if rg -q --fixed-strings "$TEST_KEY" "${TEST_CACHE}/omarchy-steam-friends/snapshot.json"; then
  fail 'cache contains the API key'
fi

# A network outage uses only a recent, private, schema-valid cache.
FAKE_STEAM_MODE=network-failure
cached="$(run_snapshot)"
assert_jq '.ok and .configured and .stale and (.warning | length > 0)' "$cached"

# An old or permission-broad cache is never used as live presence.
jq '.generatedAt = (now - 90000 | floor)' \
  "${TEST_CACHE}/omarchy-steam-friends/snapshot.json" \
  >"${TEST_CACHE}/omarchy-steam-friends/expired.json"
mv "${TEST_CACHE}/omarchy-steam-friends/expired.json" "${TEST_CACHE}/omarchy-steam-friends/snapshot.json"
chmod 600 "${TEST_CACHE}/omarchy-steam-friends/snapshot.json"
expired_cache="$(run_snapshot)"
assert_jq '(.ok | not) and .configured and (.stale | not)' "$expired_cache"

FAKE_STEAM_MODE=normal
fresh_snapshot="$(run_snapshot)"
assert_jq '.ok and (.stale | not)' "$fresh_snapshot"
chmod 644 "${TEST_CACHE}/omarchy-steam-friends/snapshot.json"
FAKE_STEAM_MODE=network-failure
broad_cache="$(run_snapshot)"
assert_jq '(.ok | not) and .configured and (.stale | not)' "$broad_cache"

# An arbitrary JSON cache is rejected instead of crossing into QML.
printf '%s\n' '[]' >"${TEST_CACHE}/omarchy-steam-friends/snapshot.json"
chmod 600 "${TEST_CACHE}/omarchy-steam-friends/snapshot.json"
invalid_cache="$(run_snapshot)"
assert_jq '(.ok | not) and .configured and (.stale | not)' "$invalid_cache"

# Group/world-readable and symlinked credential files are rejected before curl.
FAKE_STEAM_MODE=normal
write_config
chmod 644 "${TEST_CONFIG}/omarchy/steam-friends.json"
before_calls="$(wc -l <"$FAKE_CURL_LOG")"
insecure_config="$(run_snapshot)"
after_calls="$(wc -l <"$FAKE_CURL_LOG")"
assert_jq '.configured == false' "$insecure_config"
[[ "$before_calls" == "$after_calls" ]] || fail 'insecure config reached curl'

write_config
mv "${TEST_CONFIG}/omarchy/steam-friends.json" "${TEST_CONFIG}/omarchy/credentials-target.json"
ln -s "${TEST_CONFIG}/omarchy/credentials-target.json" "${TEST_CONFIG}/omarchy/steam-friends.json"
symlink_config="$(run_snapshot)"
assert_jq '.configured == false' "$symlink_config"

# Untrusted IDs from a malformed API response fail closed.
unlink "${TEST_CONFIG}/omarchy/steam-friends.json"
mv "${TEST_CONFIG}/omarchy/credentials-target.json" "${TEST_CONFIG}/omarchy/steam-friends.json"
FAKE_STEAM_MODE=invalid-friend-id
invalid_response="$(run_snapshot)"
assert_jq '(.ok | not) and .configured and (.error | contains("unexpected friends response"))' "$invalid_response"

printf '%s\n' 'security tests passed'
