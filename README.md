# Solaarchy

Every connected Logitech device at a glance, in the
[Omarchy](https://omarchy.org/) bar: how much battery each one has left, which
ones are awake, the keyboard backlight, and the haptics of a mouse that has
them — one click away, without opening an app. Read through
[Solaar](https://github.com/pwr-Solaar/Solaar).

<img src="screenshots/panel.png" alt="Solaarchy panel with a keyboard and a mouse, MX Master 4 charging" width="396">

- Battery level, charging state and a charge bar for each device
- Live updates: a device that switches off or goes to sleep shows as **Asleep**
  right away with its last reading; one that wakes, or a receiver plugged in or
  out, triggers a fresh read. No fast polling.
- One notification per discharge when a device drops below the low-battery
  threshold
- Keyboard backlight on/off: the bulb next to each keyboard's name, or
  right-click the bar icon
- Haptics, on mice that have a haptic motor (MX Master 4): the haptic level,
  and a pulse for the events you pick in the panel — notifications, Hyprland
  events like a window asking for attention, low battery — or from any
  script. See [Haptics](#haptics)
- The widget hides itself while no receiver is plugged in (optional)
- Bar icon picker in its own sub-panel, and a one-click way to open Solaar
- Last readings survive shell restarts

Solaarchy ships no vendor logos and is not affiliated with, or endorsed by,
Logitech or the Solaar project.

## Screenshots

<table>
  <tr>
    <td align="center" valign="top">
      <img src="screenshots/bar-tooltip.png" alt="Tooltip on the bar icon listing each device's battery and the backlight state" width="357"><br>
      <sub>Hover the bar icon for every battery level at a glance</sub>
    </td>
    <td align="center" valign="top">
      <img src="screenshots/panel-backlight-hint.png" alt="Backlight bulb next to the keyboard name with its hint" width="387"><br>
      <sub>The bulb next to a keyboard switches its backlight</sub>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="screenshots/panel-asleep.png" alt="A sleeping keyboard keeps its last reading, with the keyboard and mouse bar icon" width="393"><br>
      <sub>A sleeping keyboard keeps its last reading; bar icon: keyboard + mouse</sub>
    </td>
    <td align="center" valign="top">
      <img src="screenshots/icon-picker.png" alt="The bar icon picker: the Solaar icon, the device icons, and a YOUR OWN row holding two user-supplied SVGs and the + button" width="272"><br>
      <sub>Customise the bar icon: Solaar's own, a device icon, or any SVG you
      add yourself with <b>+</b></sub>
    </td>
  </tr>
</table>

The panel follows your Omarchy theme; these shots use several different ones.

## Requirements

- Omarchy with the Quattro shell
- **Solaar**, from the official Arch repositories:

  ```sh
  omarchy pkg add solaar
  ```

  It brings the Python library Solaarchy reads through and the udev rule that
  lets your user access Logitech receivers. Log out and back in (or replug the
  receiver) after installing it for the first time.

- Recommended: keep the Solaar app running in the background, so backlight
  changes are remembered and re-applied when the keyboard wakes. Add this to
  `~/.config/hypr/autostart.lua`:

  ```lua
  o.launch_on_start("solaar --window=hide")
  ```

## Install

```sh
omarchy plugin add https://github.com/C50NK4/Solaarchy.git --enable
```

## Usage

| On the bar icon | Does                               |
| --------------- | ---------------------------------- |
| Left-click      | Open or close the panel            |
| Right-click     | Toggle the keyboard backlight      |
| Middle-click    | Open Solaar                        |

In the panel:

- The **bulb** next to a keyboard's name switches its backlight.
- The **vibrate** button next to a haptic mouse's name opens its
  [haptics](#haptics): the level, and which events buzz.
- **Solaar** on the DEVICES line opens Solaar, for pairing, buttons, DPI and
  everything else.
- The **palette** next to Refresh opens the bar icon picker; the back arrow or
  Escape returns to the devices.

Arrow keys move between controls, Enter activates, and Escape closes.

The panel can also be opened from a script:

```sh
omarchy-shell shell summon io.github.c50nk4.solaarchy '{}'
```

## Haptics

Mice with a haptic motor, like the MX Master 4, get a vibrate button next to
their name. It opens a page with:

- **Level**: off, low, medium, high or max (25/50/75/100, Solaar's own steps).
  It's changed through `solaar config`, exactly like the backlight, so a
  running Solaar app keeps it. A short pulse plays at the new level.
- **Alerts** and **Desktop**: one row per event, showing the waveform it
  plays. Click a row to pick from Off and a tile for each waveform the mouse
  can play; picking one saves it and plays it, so choosing is also trying.
- **Quiet in fullscreen**: no desktop haptics while a fullscreen window is
  focused, such as a game or a video.

<table>
  <tr>
    <td align="center" valign="top">
      <img src="screenshots/haptics-button.png" alt="The MX Master 4 row in the panel, with the vibrate button after its name" width="300"><br>
      <sub>The vibrate button opens the haptics page</sub><br><br>
      <img src="screenshots/haptics-picker.png" alt="The waveform picker for Window wants attention: what triggers it, Off, and a tile per waveform with Sharp collision selected" width="300"><br>
      <sub>An event's picker: each tile plays as it's picked</sub>
    </td>
    <td align="center" valign="top">
      <img src="screenshots/haptics-page.png" alt="The haptics page: level buttons, the alert and desktop events with their waveforms, and the Quiet in fullscreen switch" width="300"><br>
      <sub>Level, every event and its waveform, and quiet in fullscreen</sub>
    </td>
  </tr>
</table>

### Events

Every event is a setting that holds a waveform name, or `off`. The quiet
alerts start out on: low battery, a window asking for attention, the terminal
bell and critical notifications. The busy desktop events start out off.
Pick them in the panel, or from the terminal; per-app notification waveforms
are terminal-only:

```sh
omarchy bar set io.github.c50nk4.solaarchy hapticUrgent knock
omarchy bar set io.github.c50nk4.solaarchy hapticNotifications subtle-collision
omarchy bar set io.github.c50nk4.solaarchy hapticNotificationApps "slack=happy-alert, spotify=off"
```

| Setting                       | Buzzes when                                                       |
| ----------------------------- | ----------------------------------------------------------------- |
| `hapticLowBattery`            | Solaarchy sends its low-battery notification (default `angry-alert`) |
| `hapticNotifications`         | any desktop notification arrives                                  |
| `hapticNotificationsCritical` | a critical-urgency notification arrives, instead of the one above (default `sharp-state-change`) |
| `hapticNotificationApps`      | per app, overriding both: `app=waveform, app=off, …`              |
| `hapticUrgent`                | a window that has been open a few seconds asks for attention (default `sharp-collision`); apps asking as they launch are left to `hapticWindowOpen` |
| `hapticBell`                  | something rings the system bell, e.g. a terminal (default `whisper-collision`) |
| `hapticWorkspace`             | the active workspace changes                                      |
| `hapticWindowOpen`            | a window opens                                                    |
| `hapticWindowClose`           | a window closes                                                   |
| `hapticWindowMoved`           | a window is sent to another workspace                             |
| `hapticFullscreen`            | the focused window enters or leaves fullscreen                    |
| `hapticFloating`              | a window switches between tiled and floating                      |
| `hapticScreencast`            | screen sharing or recording starts or stops                       |
| `hapticMonitor`               | a monitor is connected or disconnected                            |
| `hapticSubmap`                | a keybind submap is entered or left                               |
| `hapticLayout`                | the keyboard layout switches                                      |
| `hapticPauseFullscreen`       | `true`: no Hyprland event haptics while a fullscreen window is focused (games, video) |

Waveforms: `sharp-state-change`, `damp-state-change`, `sharp-collision`,
`damp-collision`, `subtle-collision`, `whisper-collision`, `happy-alert`,
`angry-alert`, `completed`, `knock`, `square`, `wave`, `firework`, `mad`,
`jingle`, `ringing`. Each one plays as you pick it on the haptics page.

Per-app names are the ones notifications are sent with, lowercased; run
`dbus-monitor "interface='org.freedesktop.Notifications'"` and look at the
first string of a `Notify` call to find an app's.

A burst of events (scrolling through workspaces, say) plays one pulse, not a
rattle.

### From scripts

`solaarchy-haptics.py` in the plugin folder plays a waveform on demand:

```sh
~/.config/omarchy/plugins/io.github.c50nk4.solaarchy/solaarchy-haptics.py play completed
~/.config/omarchy/plugins/io.github.c50nk4.solaarchy/solaarchy-haptics.py list
```

While the widget runs, it hands the request to the widget's player and
returns at once. Without it, it finds the mouse itself, which takes about a
second. Link it into your `PATH` to keep it short:

```sh
ln -s ~/.config/omarchy/plugins/io.github.c50nk4.solaarchy/solaarchy-haptics.py ~/.local/bin/solaarchy-haptic
```

A bind in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + H", "Haptic knock", "solaarchy-haptic play knock")
```

Or a pulse when Claude Code finishes a turn, in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command", "command": "solaarchy-haptic play completed" }] }]
  }
}
```

`--device ID` picks one device when more than one has haptics; the id is the
one `list` prints.

## Configure

All settings are available in the Omarchy bar settings, or from the terminal:

```sh
omarchy bar set io.github.c50nk4.solaarchy icon mouse
omarchy bar set io.github.c50nk4.solaarchy lowThreshold 20
omarchy bar set io.github.c50nk4.solaarchy hideWhenDisconnected false --json
omarchy bar move io.github.c50nk4.solaarchy --section right
```

| Setting                | Default  | Meaning                                                                            |
| ---------------------- | -------- | ---------------------------------------------------------------------------------- |
| `icon`                 | `solaar` | Bar icon, see below                                                                |
| `customIcon`           | *(empty)*| File name of your own SVG, without `.svg`. Overrides `icon` while set              |
| `customIconDir`        | *(empty)*| Folder scanned for your own SVGs. Empty means `~/.config/omarchy/solaarchy/icons`  |
| `lowThreshold`         | `15`     | Battery % at or below which the icon turns urgent and a notification is sent      |
| `refreshIntervalSec`   | `300`    | Backup poll. Connection changes are picked up immediately either way               |
| `hideWhenDisconnected` | `true`   | Hide the widget while no Logitech receiver or device is connected                 |

### Bar icons

| Icons                                                              | Values                                                               |
| ------------------------------------------------------------------ | -------------------------------------------------------------------- |
| Solaar's own icon (default)                                        | `solaar`                                                             |
| Mouse, filled and outline                                          | `mouse`, `mouse-outline`                                             |
| Keyboard, filled and outline                                       | `keyboard`, `keyboard-outline`                                       |
| Keyboard + mouse, filled and outline                               | `combo`, `combo-outline`                                             |

Sources and licenses: [THIRD_PARTY.md](THIRD_PARTY.md).

### Your own bar icon

Solaarchy ships no vendor logos — no Logitech mark, no anyone else's. Those are
trademarks, and a plugin that hands them out is distributing artwork it has no
licence to, however small the icon is. Solaar itself takes the same line: it
uses the word "Logitech" to say what hardware it supports, and every icon it
ships is its own.

That leaves a real wish unserved: plenty of people are fond of their hardware
and want its mark in their own bar. So instead of shipping the artwork,
Solaarchy renders whatever SVG **you** supply.

Open the bar icon picker (the palette next to Refresh) and click **+** under
**YOUR OWN**. Pick an `.svg` file, and it is copied into
`~/.config/omarchy/solaarchy/icons/` and selected right away — no terminal, no
config file.

Every `.svg` in that folder is a tile of its own, so keep as many as you like
and switch between them in one click. Copying files in by hand works just as
well, and the folder is watched, so anything you add or remove shows up without
restarting the shell. From the terminal:

```sh
omarchy bar set io.github.c50nk4.solaarchy customIcon my-logo   # the file name, no .svg
omarchy bar set io.github.c50nk4.solaarchy customIcon ""        # back to the built-in icon
```

Notes:

- The icon takes your Omarchy theme's bar colour, exactly like every built-in
  icon, and turns urgent-red with the rest of the widget on low battery. So a
  single-colour silhouette works best: a multi-colour logo still renders, but
  as one solid shape.
- Proportions come from the file's `viewBox`, so a wide wordmark gets a wide
  slot instead of being squashed.
- What you put there is yours and stays on your machine. Using someone's
  trademark on your own desktop is your call; Solaarchy neither ships nor
  fetches it.

## Supported hardware

Developed and used daily with:

- **Bolt Receiver**
- **MX Keys Mini for Business** (battery + backlight)
- **MX Master 4** (battery + haptics)

Beyond that, anything Solaar can see:

- Bolt, Unifying, Nano, Lightspeed and 27 MHz receivers, with every device
  paired to them
- HID++ devices connected by USB cable or Bluetooth

Not supported: receivers Solaar doesn't know (some very basic Nano receivers,
such as the one sold with the M185) and Logitech devices without HID++ (plain
wired mice, most webcams and many headsets).

The backlight switch turns the backlight on or off. "On" is the first on-mode
Solaar offers for the keyboard: Automatic where the keyboard supports it,
otherwise Enabled or Manual. Brightness levels are left to the keyboard and
Solaar.

## How it works, and what it touches

Plugins run unsandboxed inside the Omarchy shell, so here is everything
Solaarchy does:

- **Reading devices:** `solaarchy-status.py` uses Solaar's Python library to
  ask each device for its battery and backlight state. It runs when the panel
  opens, after connection changes, and every `refreshIntervalSec`. It does not
  change any device setting and never writes Solaar's configuration. Reads are
  serialized with a lock file in a directory only you can write to
  (`$XDG_RUNTIME_DIR`, else `~/.cache/solaarchy`), never a shared one like
  `/tmp`, and every read is double-checked, because HID++ replies from other programs (the Solaar app
  included) can otherwise be mistaken for its own.
- **Watching connections:** `solaarchy-monitor.py` runs for as long as the
  widget is enabled. It opens the Logitech receivers' `/dev/hidraw*` nodes
  read-only and listens for connect/disconnect messages and USB hotplug
  events. It never writes to a device. The kernel stops it together with the
  shell.
- **Playing haptics:** `solaarchy-haptics.py` runs for as long as a device
  with haptics is known. It keeps that device open through Solaar's library
  and asks it to play a waveform (HID++ feature 0x19B0, the request behind
  `solaar config <device> haptic-play`) when an event you picked happens, or
  when you run it with `play`. That changes no device setting. It listens for
  `play` on a socket in `$XDG_RUNTIME_DIR` (else `~/.cache/solaarchy`) that
  only you can open, removed when it stops.
- **Watching notifications:** only while a notification haptic is set, which
  critical notifications are by default. The player then runs `dbus-monitor`
  on your session bus for `Notify` calls and reads the sending app's name and
  the urgency, never the text. Turning every notification haptic off (in the
  panel or the settings) stops it.
- **Changing things:** only when you ask. Toggling the backlight runs
  `solaar config <device> backlight …`, and picking a haptic level runs
  `solaar config <device> haptic-level …`. Picking an event's waveform runs
  `omarchy bar set … <setting> <waveform>`. Picking a bar icon runs
  `omarchy bar set … icon …`. Opening Solaar runs `uwsm-app -- solaar`.
- **Files:** last readings are saved to
  `~/.local/state/omarchy/solaarchy.json`. Settings live in
  `~/.config/omarchy/shell.json` like every bar widget's.
- **Notifications:** sent with `notify-send -a Solaarchy`.
- **Privileges:** none. No sudo, no udev rule or system service of its own;
  hardware access comes from Solaar's udev rule.

## Troubleshooting

- **"solaar library unavailable"**: Solaar isn't installed, see Requirements.
- **"could not open 046d:…: Permission denied"**: Solaar's udev rule hasn't
  applied yet. Replug the receiver or log out and back in.
- **The widget doesn't appear**: nothing Logitech is connected and
  `hideWhenDisconnected` is on. Run
  `omarchy plugin list --json | jq '.[] | select(.id == "io.github.c50nk4.solaarchy")'`
  to check that it's enabled, and `qs log -p "$OMARCHY_PATH/shell" --tail 100`
  for errors.
- **Backlight turns back on or off by itself**: the Solaar app is not
  running, or was running with a different saved setting. Start it as shown
  under Requirements.
- **No haptic pulse**: check the level on the haptics page isn't Off, and that
  the event's setting holds a waveform name (anything else counts as `off`).
  A mouse that just woke up is found again a moment after it reconnects.

## Update

```sh
omarchy plugin update io.github.c50nk4.solaarchy
```

## Remove

```sh
omarchy plugin remove io.github.c50nk4.solaarchy
rm -f ~/.local/state/omarchy/solaarchy.json
```

Removing the plugin stops the connection watcher and the haptics player with it. Solaar itself is
left installed.

To only take it off the bar and keep it installed:

```sh
omarchy plugin disable io.github.c50nk4.solaarchy
```

## License

Code: [MIT](LICENSE). Icons: see [THIRD_PARTY.md](THIRD_PARTY.md).
