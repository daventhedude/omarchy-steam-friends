# Privacy and Steam Data Notice

Effective: August 17, 2026

Steam Friends is a local, open-source Omarchy plugin. It has no developer-operated backend, telemetry, analytics, advertising, or account system. The maintainer does not receive your API key, Steam data, searches, or usage data.

## What you request

When you configure the plugin with your own standard Steam Web API user key, you direct it to retrieve data needed for the friends panel:

- your Steam ID;
- your public friend IDs and friendship timestamps;
- public player-summary fields returned for you and those friends: display and real names, avatar URLs, presence state, current game name and app ID, last-logoff time, and country code.

Steam may return additional fields. The helper discards them before caching or sending data to QML. The plugin never asks for, intercepts, or stores your Steam password.

## Purpose and recipients

The data is used only to render the panel, search it locally, open a profile or Steam chat at your request, and preserve a short offline snapshot. Requests go directly from your computer to Valve's Steam Web API. Avatar requests go directly to allowlisted Valve-operated Steam CDN hosts. No Steam data is sent to the maintainer or another project-controlled service.

## Local storage and country

Your API key and Steam ID are stored in `~/.config/omarchy/steam-friends.json` until you delete them. A normalized, key-free presence snapshot is stored in `~/.cache/omarchy-steam-friends/snapshot.json`. That file remains until it is replaced or you delete it; once it is more than 24 hours old, the plugin rejects it instead of displaying it. The same private cache directory contains a lock file and a numeric timestamp used only to serialize Steam startup actions; neither contains a Steam ID or action history. While Omarchy is running, its QML image engine may also retain decoded avatars in its in-process image cache.

Both files remain solely on the computer where you install the plugin. They are therefore stored in the country where you physically locate that computer; the project does not choose, know, or transfer them to a developer-controlled storage country. You are responsible for choosing a device location permitted by your obligations and the Steam Web API Terms.

Remove both local stores with:

```bash
gio trash ~/.config/omarchy/steam-friends.json ~/.cache/omarchy-steam-friends
```

You can also revoke the key from Steam's Web API key page. Removing only the plugin intentionally leaves the two local stores in place for a later reinstall.

## Steam terms and disclaimer

Your use of the Web API and Steam data is governed by the [Steam Web API Terms of Use](https://steamcommunity.com/dev/apiterms). You supply and remain responsible for your own user key. Do not use a publisher key or somebody else's key.

Steam's Web API, Steam data, and Valve brand links are provided **as is**, **with all faults**, and **as available**. To the maximum extent allowed by applicable law, Valve, Steam publishers and developers, and their suppliers make no express, statutory, or implied warranties, including warranties of merchantability, fitness, accuracy, title, non-infringement, or uninterrupted and error-free access. They are not liable for damages arising from use of the Web API, Steam data, or Valve brand links, including indirect, consequential, special, incidental, or punitive damages, even if advised that such damages were possible. Where the law does not permit an exclusion, it applies only to the maximum permitted extent. If you do not accept those terms, discontinue use and delete the locally stored Steam data.

Steam Friends is an independent community project. It is not endorsed by, affiliated with, or provided by Valve or Steam. Steam and the Steam logo are trademarks of Valve Corporation.

The plugin itself remains covered by its [MIT license](LICENSE), including that license's separate warranty and liability disclaimer.
