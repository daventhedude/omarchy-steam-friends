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
FAKE_XDG_LOG="${AUDIT_TMP}/xdg-open.log"
TEST_ACTION_CACHE="${AUDIT_TMP}/action-cache"
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
    EXPECTED_SELF_ID="$TEST_SELF_ID" \
    EXPECTED_SUMMARY_IDS="${TEST_SELF_ID},${TEST_FRIEND_ONE},${TEST_FRIEND_TWO}" \
    FAKE_STEAM_MODE="${FAKE_STEAM_MODE:-normal}" \
    "$BACKEND" snapshot
}

run_setup() {
  printf '%s\n%s\n\n' "$TEST_SELF_ID" "$TEST_KEY" | env \
    HOME="$TEST_HOME" \
    XDG_CONFIG_HOME="$TEST_CONFIG" \
    XDG_CACHE_HOME="$TEST_CACHE" \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    TERM=xterm \
    FAKE_CURL_LOG="$FAKE_CURL_LOG" \
    EXPECTED_KEY="$TEST_KEY" \
    EXPECTED_SELF_ID="$TEST_SELF_ID" \
    EXPECTED_SUMMARY_IDS="$TEST_SELF_ID" \
    FAKE_STEAM_MODE=normal \
    "$BACKEND" setup
}

run_steam_action() {
  env \
    HOME="$TEST_HOME" \
    XDG_CONFIG_HOME="$TEST_CONFIG" \
    XDG_CACHE_HOME="$TEST_ACTION_CACHE" \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    FAKE_XDG_LOG="$FAKE_XDG_LOG" \
    FAKE_XDG_MODE="${FAKE_XDG_MODE:-delayed-ready}" \
    FAKE_STEAM_PID_FILE="${AUDIT_TMP}/fake-steam.pid" \
    FAKE_PGREP_RUNNING="${FAKE_PGREP_RUNNING:-0}" \
    "$BACKEND" steam-action "$@"
}

mkdir -p "$TEST_HOME" "$TEST_BIN"

if rg -q --fixed-strings -- '--arg apiKey' "$BACKEND"; then
  fail 'setup exposes the API key through a subprocess argument'
fi
if rg -q -- '--argjson (previous|next|friends|players)' "$BACKEND"; then
  fail 'Steam collections are exposed to the process argument-size limit'
fi
jq -e '.barWidget.schema[] | select(.key == "refreshIntervalSec") | .min >= 60' \
  "${REPO_ROOT}/manifest.json" >/dev/null \
  || fail 'UI refresh floor can exceed the documented Steam request budget'
rg -q --fixed-strings 'Math.max(60,' "${REPO_ROOT}/Panel.qml" \
  || fail 'runtime refresh floor can exceed the documented Steam request budget'

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
  [[ "$(rg -c '^data-urlencode = ' <<<"$config")" == "2" ]] || exit 96
  [[ "$config" == *"data-urlencode = \"steamid=${EXPECTED_SELF_ID}\""* ]] || exit 97
  [[ "$config" == *'data-urlencode = "relationship=friend"'* ]] || exit 98
  if [[ "$FAKE_STEAM_MODE" == "invalid-friend-id" ]]; then
    printf '%s\n' '{"friendslist":{"friends":[{"steamid":"not-a-steamid","friend_since":1700000000}]}}'
  elif [[ "$FAKE_STEAM_MODE" == "large" ]]; then
    jq -cn '{friendslist: {friends: [range(1; 5001) | {
      steamid: (("00000000000000000" + tostring)[-17:]),
      friend_since: 1700000000
    }]}}'
  else
    printf '%s\n' '{"friendslist":{"friends":[{"steamid":"00000000000000001","friend_since":1700000000},{"steamid":"00000000000000002","friend_since":1710000000}]}}'
  fi
  exit 0
fi

if [[ "$config" == *'/GetPlayerSummaries/v2/'* ]]; then
  [[ "$(rg -c '^data-urlencode = ' <<<"$config")" == "1" ]] || exit 96
  if [[ "$FAKE_STEAM_MODE" == "large" ]]; then
    summary_ids="$(sed -n 's/^data-urlencode = "steamids=\([0-9,]*\)"$/\1/p' <<<"$config")"
    [[ -n "$summary_ids" ]] || exit 99
    jq -cn --arg ids "$summary_ids" '{response: {players: ($ids | split(",") | map({
      steamid: ., personaname: ("Friend " + .), personastate: 1
    }))}}'
    exit
  fi
  [[ "$config" == *"data-urlencode = \"steamids=${EXPECTED_SUMMARY_IDS}\""* ]] || exit 99
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

cat >"${TEST_BIN}/xdg-open" <<'FAKE_XDG_OPEN'
#!/usr/bin/env bash
set -euo pipefail

(( $# == 1 )) || exit 90
printf '%s\n' "$1" >>"$FAKE_XDG_LOG"

case "$FAKE_XDG_MODE" in
  delayed-ready)
    (
      sleep 0.25
      mkdir -p -- "$HOME/.steam"
      [[ -e "$HOME/.steam/steam.pipe" ]] || mkfifo "$HOME/.steam/steam.pipe"
    ) &
    ;;
  ready)
    mkdir -p -- "$HOME/.steam"
    [[ -e "$HOME/.steam/steam.pipe" ]] || mkfifo "$HOME/.steam/steam.pipe"
    ;;
  long-lived)
    # A cold xdg-open launch leaves Steam running long after the action ends,
    # holding every file descriptor it inherited.
    mkdir -p -- "$HOME/.steam"
    [[ -e "$HOME/.steam/steam.pipe" ]] || mkfifo "$HOME/.steam/steam.pipe"
    sleep 30 >/dev/null 2>&1 </dev/null &
    printf '%s\n' "$!" >"$FAKE_STEAM_PID_FILE"
    ;;
  fail) exit 1 ;;
  *) exit 91 ;;
esac
FAKE_XDG_OPEN
chmod 700 "${TEST_BIN}/xdg-open"

cat >"${TEST_BIN}/pgrep" <<'FAKE_PGREP'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == *'-x steam'* ]] || exit 1
[[ "$FAKE_PGREP_RUNNING" == "1" ]] && exit 0
[[ -p "$HOME/.steam/steam.pipe" ]]
FAKE_PGREP
chmod 700 "${TEST_BIN}/pgrep"

# Unconfigured startup is deterministic and does not contact Steam.
unconfigured="$(run_snapshot)"
assert_jq '.configured == false and .ok == false and (.friends | length == 0)' "$unconfigured"
[[ ! -e "$FAKE_CURL_LOG" ]] || fail 'unconfigured snapshot contacted curl'

# A valid private config produces a bounded, normalized snapshot.
write_config
snapshot="$(run_snapshot)"
assert_jq '.ok and .configured and (.friends | length == 2)' "$snapshot"
assert_jq '.accountId == "00000000000000000"' "$snapshot"
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

# A fresh, account-bound cache rate-limits repeat requests without contacting
# curl, then remains available as stale data during a real network outage.
FAKE_STEAM_MODE=network-failure
before_calls="$(wc -l <"$FAKE_CURL_LOG")"
rate_limited="$(run_snapshot)"
after_calls="$(wc -l <"$FAKE_CURL_LOG")"
assert_jq '.ok and (.stale | not) and (.warning == "")' "$rate_limited"
[[ "$before_calls" == "$after_calls" ]] || fail 'fresh cache did not rate-limit curl'
jq '.generatedAt = (now - 61 | floor)' \
  "${TEST_CACHE}/omarchy-steam-friends/snapshot.json" \
  >"${TEST_CACHE}/omarchy-steam-friends/aged.json"
mv "${TEST_CACHE}/omarchy-steam-friends/aged.json" "${TEST_CACHE}/omarchy-steam-friends/snapshot.json"
chmod 600 "${TEST_CACHE}/omarchy-steam-friends/snapshot.json"
cached="$(run_snapshot)"
assert_jq '.ok and .configured and .stale and (.warning | length > 0)' "$cached"

# A structurally valid cache from a different configured account is rejected.
jq '.accountId = "99999999999999999"' \
  "${TEST_CACHE}/omarchy-steam-friends/snapshot.json" \
  >"${TEST_CACHE}/omarchy-steam-friends/mismatched.json"
mv "${TEST_CACHE}/omarchy-steam-friends/mismatched.json" "${TEST_CACHE}/omarchy-steam-friends/snapshot.json"
chmod 600 "${TEST_CACHE}/omarchy-steam-friends/snapshot.json"
mismatched_cache="$(run_snapshot)"
assert_jq '(.ok | not) and .configured and (.stale | not)' "$mismatched_cache"

# An old or permission-broad cache is never used as live presence.
jq --arg accountId "$TEST_SELF_ID" \
  '.accountId = $accountId | .generatedAt = (now - 90000 | floor)' \
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

chmod 600 "${TEST_CACHE}/omarchy-steam-friends/snapshot.json"
chmod 755 "${TEST_CACHE}/omarchy-steam-friends"
broad_cache_dir="$(run_snapshot)"
assert_jq '(.ok | not) and .configured and (.stale | not)' "$broad_cache_dir"
chmod 700 "${TEST_CACHE}/omarchy-steam-friends"

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

# A hardlinked credential file is rejected even when its mode is private.
unlink "${TEST_CONFIG}/omarchy/steam-friends.json"
mv "${TEST_CONFIG}/omarchy/credentials-target.json" "${TEST_CONFIG}/omarchy/steam-friends.json"
ln "${TEST_CONFIG}/omarchy/steam-friends.json" "${TEST_CONFIG}/omarchy/credentials-hardlink.json"
hardlinked_config="$(run_snapshot)"
assert_jq '.configured == false' "$hardlinked_config"
unlink "${TEST_CONFIG}/omarchy/credentials-hardlink.json"

# Steam URI actions are validated, serialized, and guarded across helper
# processes. This is the regression contract for a real cold-start crash where
# three impatient Enter presses launched competing Steam clients.
FAKE_XDG_MODE=delayed-ready run_steam_action chat "$TEST_FRIEND_ONE" &
first_action_pid=$!
for _ in {1..50}; do
  [[ -s "$FAKE_XDG_LOG" ]] && break
  sleep 0.02
done
[[ -s "$FAKE_XDG_LOG" ]] || fail 'first Steam action never reached xdg-open'

set +e
FAKE_XDG_MODE=delayed-ready run_steam_action main
parallel_action_status=$?
set -e
[[ "$parallel_action_status" == "75" ]] \
  || fail 'parallel Steam action was not rejected with temporary-failure status'
wait "$first_action_pid" || fail 'serialized Steam action did not become ready'
[[ "$(wc -l <"$FAKE_XDG_LOG")" == "1" ]] \
  || fail 'parallel Steam action reached xdg-open'
[[ "$(<"$FAKE_XDG_LOG")" == "steam://friends/message/${TEST_FRIEND_ONE}" ]] \
  || fail 'Steam chat URI was not reconstructed from the validated ID'

set +e
FAKE_XDG_MODE=ready run_steam_action main
guarded_action_status=$?
FAKE_XDG_MODE=ready run_steam_action chat 'not-a-steam-id'
invalid_action_status=$?
FAKE_XDG_MODE=ready run_steam_action friends
obsolete_action_status=$?
set -e
[[ "$guarded_action_status" == "75" ]] \
  || fail 'post-start Steam action guard did not reject a duplicate'
[[ "$invalid_action_status" == "64" ]] \
  || fail 'invalid Steam action input did not fail closed'
[[ "$obsolete_action_status" == "64" ]] \
  || fail 'non-allowlisted Steam action kind did not fail closed'
[[ "$(wc -l <"$FAKE_XDG_LOG")" == "1" ]] \
  || fail 'guarded or invalid Steam action reached xdg-open'
[[ "$(stat -c '%a' "$TEST_ACTION_CACHE/omarchy-steam-friends")" == "700" ]] \
  || fail 'Steam action cache directory mode is not 0700'
[[ "$(stat -c '%a' "$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.lock")" == "600" ]] \
  || fail 'Steam action lock mode is not 0600'
[[ "$(stat -c '%a' "$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.guard")" == "600" ]] \
  || fail 'Steam action guard mode is not 0600'
if rg -q --fixed-strings "$TEST_FRIEND_ONE" "$TEST_ACTION_CACHE/omarchy-steam-friends"; then
  fail 'Steam action guard persisted a friend ID'
fi

future_guard="$(( $(date +%s) + 3600 ))"
printf '%s\n' "$future_guard" \
  >"$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.guard"
chmod 600 "$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.guard"
set +e
FAKE_XDG_MODE=ready run_steam_action main
future_guard_status=$?
set -e
[[ "$future_guard_status" == "75" ]] \
  || fail 'implausible future action guard did not fail safely'
recovered_guard="$(<"$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.guard")"
now_epoch="$(date +%s)"
(( recovered_guard >= now_epoch && recovered_guard <= now_epoch + 46 )) \
  || fail 'implausible future action guard did not recover to a bounded delay'
[[ "$(wc -l <"$FAKE_XDG_LOG")" == "1" ]] \
  || fail 'future timestamp recovery reached xdg-open'

unlink "$TEST_HOME/.steam/steam.pipe"
printf '%s\n' 0 >"$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.guard"
chmod 600 "$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.guard"
set +e
FAKE_PGREP_RUNNING=1 FAKE_XDG_MODE=ready run_steam_action main
slow_start_status=$?
set -e
[[ "$slow_start_status" == "75" ]] \
  || fail 'live Steam process without a command pipe was not treated as starting'
[[ "$(wc -l <"$FAKE_XDG_LOG")" == "1" ]] \
  || fail 'slow Steam startup launched a competing client'

# The allowlisted main-window action is reconstructed internally and reaches
# xdg-open only after the same private serialization boundary as chat actions.
printf '%s\n' 0 >"$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.guard"
chmod 600 "$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.guard"
FAKE_XDG_MODE=ready run_steam_action main \
  || fail 'Steam main-window action did not complete'
[[ "$(tail -n 1 "$FAKE_XDG_LOG")" == "steam://open/main" ]] \
  || fail 'Steam main-window URI was not reconstructed from the allowlisted action'

# The serialization lock must not leak into the Steam client that xdg-open
# starts. A leaked descriptor keeps the lock held for Steam's whole lifetime,
# silently rejecting every later chat action with the temporary-failure status.
printf '%s\n' 0 >"$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.guard"
chmod 600 "$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.guard"
FAKE_XDG_MODE=long-lived run_steam_action main \
  || fail 'long-lived Steam launch did not complete'
fake_steam_pid="$(<"${AUDIT_TMP}/fake-steam.pid")"
printf '%s\n' 0 >"$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.guard"
chmod 600 "$TEST_ACTION_CACHE/omarchy-steam-friends/steam-action.guard"
set +e
FAKE_PGREP_RUNNING=1 FAKE_XDG_MODE=ready run_steam_action chat "$TEST_FRIEND_ONE"
after_launch_status=$?
set -e
kill "$fake_steam_pid" 2>/dev/null || true
[[ "$after_launch_status" == "0" ]] \
  || fail 'Steam client inherited the action lock and blocked a later chat'
[[ "$(tail -n 1 "$FAKE_XDG_LOG")" == "steam://friends/message/${TEST_FRIEND_ONE}" ]] \
  || fail 'chat after a long-lived Steam launch never reached xdg-open'

# A symlinked config parent cannot redirect credential reads.
mv "${TEST_CONFIG}/omarchy" "${TEST_CONFIG}/omarchy-target"
ln -s "${TEST_CONFIG}/omarchy-target" "${TEST_CONFIG}/omarchy"
symlink_config_dir="$(run_snapshot)"
assert_jq '.configured == false' "$symlink_config_dir"
unlink "${TEST_CONFIG}/omarchy"
mv "${TEST_CONFIG}/omarchy-target" "${TEST_CONFIG}/omarchy"

# Untrusted IDs from a malformed API response fail closed.
FAKE_STEAM_MODE=invalid-friend-id
invalid_response="$(run_snapshot)"
assert_jq '(.ok | not) and .configured and (.error | contains("unexpected friends response"))' "$invalid_response"

# The supported upper collection boundary stays functional without crossing
# the kernel's process argument-size limit.
write_config
FAKE_STEAM_MODE=large
large_snapshot="$(run_snapshot)"
assert_jq '.ok and (.counts == {total: 5000, online: 5000, inGame: 0})' "$large_snapshot"

# The interactive setup path keeps the key off stdout and writes it privately.
unlink "${TEST_CONFIG}/omarchy/steam-friends.json"
setup_output="$(run_setup)"
[[ "$setup_output" != *"$TEST_KEY"* ]] || fail 'setup printed the API key'
[[ "$setup_output" == *'PRIVACY.md'* && "$setup_output" == *'provided as-is'* ]] \
  || fail 'setup omitted the Steam data notice'
[[ "$(stat -c '%a' "${TEST_CONFIG}/omarchy/steam-friends.json")" == "600" ]] || fail 'setup config mode is not 0600'
[[ "$(stat -c '%h' "${TEST_CONFIG}/omarchy/steam-friends.json")" == "1" ]] || fail 'setup config is hardlinked'
jq -e --arg apiKey "$TEST_KEY" --arg steamId "$TEST_SELF_ID" \
  '. == {apiKey: $apiKey, steamId: $steamId}' \
  "${TEST_CONFIG}/omarchy/steam-friends.json" >/dev/null \
  || fail 'setup wrote unexpected config content'

printf '%s\n' 'security tests passed'
