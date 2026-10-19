# Cairn for Mac

A menu bar app for [Cairn](https://github.com/VedAtal/cairn), the knowledge store for coding
agents. It shows your local Cairn and your team's at a glance, and starts, stops, and opens them.

It's only an interface: the `cairn` command owns the local server, which keeps running when the
app quits. Delete the app any time and nothing about Cairn changes.

## Setup

First set up Cairn itself, if you haven't:

```sh
curl -fsSL https://raw.githubusercontent.com/VedAtal/cairn/main/install.sh | sh
```

Then the app:

```sh
~/projects/cairn-mac/setup.sh
```

That one command does everything:

1. Checks that Swift is installed. If it isn't, it opens Apple's Command Line Tools installer;
   re-run the command once that finishes. Full Xcode isn't needed.
2. Downloads the latest version from GitHub ([VedAtal/cairn-mac](https://github.com/VedAtal/cairn-mac)),
   along with [swift-app-kit](https://github.com/VedAtal/swift-app-kit), the parts it shares with
   my other menu bar apps.
3. Creates a local code-signing certificate (first run only, see
   [why](https://github.com/VedAtal/swift-app-kit#how-setupsh-fits-together)).
4. Builds Cairn and installs it to `~/Applications/Cairn.app`.
5. Launches it and sets it to start at login.

| Command | Installs |
|---|---|
| `./setup.sh` | The latest commit on GitHub (the default) |
| `./setup.sh --local` | This folder as it is, including changes you haven't committed or pushed |
| `./setup.sh --build-only` | Nothing. It just builds `build/Cairn.app` from this folder |
| `./setup.sh --uninstall` | Nothing. It removes the app ([details](#uninstall)) |

### Updating

**To the latest on GitHub:** click **Update Cairn** in the menu bar menu, or run `./setup.sh`.
This updates the app only. Update Cairn itself with `cairn upgrade`.

**To try local changes before pushing them:** run `./setup.sh --local`.

## Using it

Click the **stacked squares** in the menu bar:

```
Local: Running · v0.1.0
    42 entries · 1 project · git pushed 2 min ago
Team acme: Connected · v0.1.0
    318 entries · 6 projects · cairn.acme.dev
───────────
Open Local UI
Open Team UI
Restart Local Server
Stop Local Server
Push Git Mirror Now
Open Server Log
Update Server and CLI
```

- **Local** and **Team** always show. One you haven't set up says **Not configured**; set it up
  with `cairn local enable` or `cairn remote add`.
- **Local** can also say **Not running**, **Blocked in Login Items** (then **Allow in Login
  Items…** appears), or that something else holds its port.
- **Team** can also say **Unreachable** or **API key rejected**.
- **Open Local UI** and **Open Team UI** open the web UI, already logged in, like `cairn ui`.
- **Restart**, **Stop**, and **Start Local Server** run `cairn service restart`, `stop`, and `start`.
  A stopped server starts again with the next agent session, or at login.
- **Update Server and CLI** runs `cairn upgrade`: the CLI and the local server are one package,
  so it updates both and restarts the server. The menu's **Update Cairn** updates this app.
- **Push Git Mirror Now** shows when git mode is on (`cairn git enable`).
- The icon dims while a store you've set up can't be reached.
- If the `cairn` command isn't installed, the menu offers **Copy Install Command** instead.

### Without the app

Everything here is the `cairn` command underneath: `cairn service status`, `cairn ui`,
`cairn ui --remote`, `cairn git status`.

## Settings

Shows both stores' status. Stores are set up and changed with the `cairn` command, not here.
Below that is **Launch at login**, for the app itself.

## Uninstall

```sh
~/projects/cairn-mac/setup.sh --uninstall
```

This removes the app, its settings, the login item, and the signing certificate. It leaves Cairn
itself alone: the local server keeps running. To remove that too, run `cairn uninstall`.

## Troubleshooting

**Local says Not running.** Check `cairn service status` and the server log (**Open Server Log**,
or `~/.cairn/logs/server.log`). The login service itself is managed with `cairn service install`
and `cairn service uninstall`.

**Local says Blocked in Login Items.** The server was switched off under System Settings →
General → Login Items & Extensions → Allow in the Background, where it's listed as `cairn`.
Choose **Allow in Login Items…** and switch it back on.

**I don't see the menu bar icon.** Check that Cairn is running (`pgrep -x Cairn`). If it is, the
icon is probably hidden behind the camera notch or disallowed in System Settings → Menu Bar.

## How it works

Cairn for Mac is built on [swift-app-kit](https://github.com/VedAtal/swift-app-kit), which provides
the parts my menu bar apps share: the install script, the menu's standard items, the Settings
window layout, launch at login, and updates. This repo holds only what's specific to Cairn:

```
Sources/Cairn/
├── main.swift           Starts the app through swift-app-kit
├── AppDelegate.swift    The menu: status lines and the commands, which run the cairn CLI
├── Monitor.swift        Checks the local server every 5 s and the team server every minute
├── Server.swift         Reads ~/.cairn, runs the cairn command, and talks to the REST API
└── SettingsView.swift   Cairn's section of the Settings window
app.env                  Name, bundle ID, icons: what swift-app-kit's setup builds
setup.sh                 Fetches swift-app-kit and runs its install script
```

A few details that aren't obvious:

- **The app never owns the server.** It never writes the launchd plist or starts `cairn serve`
  itself; it runs `cairn service …`. That way people without the app get the same server, and
  quitting or updating the app can't take it down.
- **The local token is sent only to a proven server.** Before using the token in
  `~/.cairn/run/token`, the app checks the server's hello-proof (an HMAC of a fresh nonce), as the
  CLI does, so another program squatting on the port never sees it.
- **The team server is asked directly**, with the API key in `~/.cairn/credentials.toml`, because
  people who use only a team server have no local server to ask.
- **"Blocked in Login Items"** comes from `SMAppService.statusForLegacyPlist`, and shows only when
  the server is also down.

### Development

```sh
./setup.sh --local        # build and install what is in this folder right now
./setup.sh --build-only   # build and sign build/Cairn.app without installing
swift build               # just compile
```

The project builds with only the Command Line Tools, so the code avoids SwiftUI's `@State` and
`@StateObject` (their macro plugin only comes with full Xcode).
