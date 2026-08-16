# Security

Steam Friends runs inside the unsandboxed Omarchy shell process. Its security model therefore minimizes what crosses from Steam, the filesystem, and helper processes into QML.

## Data flow

1. The setup wizard accepts a user Steam ID and the user's own Steam Web API key with hidden terminal input.
2. Credentials are written atomically to `~/.config/omarchy/steam-friends.json` with mode `0600`.
3. The helper contacts only `https://api.steampowered.com/ISteamUser/GetFriendList/v1/` and `GetPlayerSummaries/v2/`.
4. The API key is supplied through Steam's documented `x-webapi-key` request header. It is never placed in a URL or process argument.
5. Responses are size-limited, schema-checked, normalized, and stripped down to the fields displayed by the panel.
6. The resulting key-free snapshot is cached for offline display.

The plugin has no telemetry and does not operate a third-party server.

## Enforced boundaries

- `curl` ignores `.curlrc`, permits only HTTPS, requires TLS 1.2 or newer, does not follow redirects, and caps every response at 2 MiB.
- API endpoints and their exact parameter shapes, Steam IDs, collection sizes, numeric ranges, text lengths, and CDN URLs are allowlisted before use. Each presence batch is reduced and bounded before accumulation.
- Steam profile URLs are constructed locally from validated 17-digit Steam IDs.
- QML performs a second validation pass and renders Steam-provided strings as plain text.
- Credential and cache files must be single-link, regular, user-owned, non-symlink files with no group or world permissions. Their direct parent directories must be real, user-owned directories; the cache directory must also have no group or world access.
- Writes use private temporary files followed by an atomic rename. The dedicated cache directory is mode `0700`; files are mode `0600`.
- The credential-handling helper fails closed unless it can set its process core-dump limit to zero before reading the API key.
- Cached presence is schema-validated, stripped of unknown fields, and expires after 24 hours.
- External programs are started with argument arrays. The plugin does not evaluate shell text, request privileges, or run installation hooks.

## Scope and limitations

The model protects against malformed Steam responses, poisoned cache/config files, URI-scheme injection, accidental key exposure through process listings or request URLs, and unsafe local file modes.

It cannot protect credentials from the same Unix user, root, a compromised Omarchy shell process, a malicious replacement for system executables, or a compromised operating system. Valve necessarily receives the API key and requested Steam IDs. Users remain subject to the [Steam Web API Terms of Use](https://steamcommunity.com/dev/apiterms).

Each user supplies their own standard user Web API key. Publisher keys and shared maintainer keys must never be used with this plugin.

## Storage and removal

- Credentials: `~/.config/omarchy/steam-friends.json`
- Presence cache: `~/.cache/omarchy-steam-friends/`

Removing the plugin leaves both locations intact so an update or reinstall does not unexpectedly destroy user data. The README documents the explicit cleanup command. A Steam key can be revoked from the user's Steam Web API key page at any time.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/daventhedude/omarchy-steam-friends/security/advisories/new). Do not include a real API key, private snapshot, or personal Steam data in a report. Revoke any key that may have been disclosed before sharing diagnostics.

The current release is the only supported security line. Run `./tests/security.sh` and `omarchy plugin validate .` when changing a trust boundary.
