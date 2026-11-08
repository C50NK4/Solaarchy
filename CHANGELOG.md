# Changelog

## Unreleased

- **Haptics**, a built-in add-on by @hypergol-d (#4): a mouse with a haptic
  motor (the MX Master 4, and any other with Solaar's HAPTIC feature) pulses
  for the events you pick. Its drawer sets the level per mouse (Off, Low, Med,
  High, Max). Its page lists the alerts (low battery, a window asking for
  attention, the terminal bell, critical notices, all notifications, screen
  sharing) and the desktop events (workspace, windows, fullscreen, floating,
  monitor, submap, keyboard layout), each with a waveform: a row opens the
  waveforms the mouse has, and picking one saves it and plays it. Quiet in
  fullscreen, per-app waveforms for notifications, and
  `addons/haptics/haptics.py play <waveform>` for scripts and keybinds. A
  player keeps the mouse open while the add-on is on, so a pulse fires at
  once. Off by default.
  A switch on the mouse's row turns haptics off and back on at the same
  level; while the add-on is off, it shows greyed and opens the add-on's page.
- **LED Effects is now off by default**, like Haptics; Circadian stays on.
  Switch it on in Settings. If you used it in 1.1.1 without ever touching its
  switch, it is off after this update.
- For add-ons: a `batteryLow(device, critical)` signal on the bar widget, and
  an optional `icon` on a row switch (`rowBulb`).
- The curated add-ons section in Settings hides while it is empty.

## 1.1.1

- **LED Effects**, a built-in add-on: a mouse with per-zone LED effects (Logitech G
  mice such as the G403, and the RGB-effect family) gets them: a master
  switch for LED control on its row, in the same place as the keyboard
  backlight switch, and in its drawer one cycler that moves every zone to
  the same next effect the firmware advertises (Disabled, Static, Cycle,
  Breathe, …), so the zones stay in lock-step, and a hue slider for the
  effects that carry a color (Static, Breathe). The drawer stays open while
  the switch is off, and a change made there turns it back on. Cycling sends
  the effect with its defaults plus any param the current effect still sets,
  so a custom Cycle period survives a trip away and back, and an effect's
  color falls back to white instead of the black Solaar's own dialog would
  leave. On by default; Settings switches it off.
- A keyboard's backlight comes back after an Easy-Switch round trip (or
  switching it off and on). Solaar re-applies the backlight it saved on every
  reconnect, and that saved value can be stale: an MX Keys Mini lit by
  Solaarchy came back dark. Solaarchy now puts back the light it had before
  its link dropped.
- Circadian no longer skips nights. It remembered only "switched on" or
  "switched off", so a keyboard that missed one dawn (asleep, or on another
  host while it was light) counted every following dusk as already done and
  stayed dark. It now remembers which dusk or dawn it switched for.
- Circadian works out dusk and dawn once a day, just after midnight, instead
  of every 10 minutes. It still switches on time: the helper now lists the
  switches for the days ahead.
- Wide bar icons are full height again. On Omarchy 4.5 the shell scales a bar
  icon's component until its longest side fits the icon size, so the keyboard
  + mouse mark and a wide SVG of your own came out about half as tall. The
  mark is drawn on the button itself now: the mouse stays at the bar's icon
  size, and a wider icon keeps that height.
- The backlight switch now takes the same lock as Solaarchy's device reads, so
  the two can't pick up each other's replies. It also gives up by itself if
  Solaar hangs.
- Rainbow LED, the mock-up, is gone: LED Effects is the real thing.
- In Settings the switches line up in one column, with the more button before
  the switch.
- DEVICES.md and addons/README.md list the devices and add-ons people use; add
  yours with a pull request.

## 1.1.0

- **Circadian**, a built-in add-on: every backlit keyboard can switch on at
  civil dusk and off at civil dawn, so it lights up when you sit down before
  sunrise even after you turned it off during the day. It has its own page
  with today as a 24-hour strip, whether it is daylight or dark outside and
  until when, the timing in minutes, and the location: Omarchy's weather
  location, else your timezone's city, or coordinates of your own. A
  keyboard's drawer can skip it. On by default; Settings switches it off.
- **A drawer per device**, behind a chevron at the end of its row:
  - Circadian for that keyboard (follow or skip)
  - Hide this device
  - the device's capabilities, read once from its HID++ feature list and
    grouped as Lighting, Haptics, Buttons, Pointer & scroll, Keyboard and
    Easy-Switch
- **Settings in the panel**, behind the gear: the built-in add-ons,
  notifications, the bar, hidden devices, and the curated and other add-ons.
  The big icon now opens the bar icon picker; the palette button is gone.
- **Notifications:**
  - the low battery one can be switched off
  - a second, urgent warning at 5 %
  - optional connected and disconnected notices, after 5 minutes without a
    link, since asleep and switched off look the same
- **Add-ons:** an Omarchy plugin with a `solaarchy-addon.json` can put its
  own controls into a device's drawer, or open its own panel for that device.
  Settings lists the built-in ones, curated ones (with links, even before
  they're installed) and any other installed ones, each with its own switch.
  Built-in add-ons live in `addons/`: Circadian, and Rainbow LED, an
  experimental mock-up that is off by default. See addons/ADDONS.md, and
  addons/skills/solaarchy-addon, a Claude Code skill for writing one. Haptics
  for the MX Master 4 is the first curated add-on, in development.
- **Auto bar icon:** `auto` and `auto-outline` draw the keyboard, the mouse,
  or both, after the devices online now (every listed one when none is), so
  the icon changes as a device switches off or comes back. They lead the
  picker's device rows, which now have four columns.
- The widget hides whenever nothing Logitech is here: no receiver, no device
  connected, none paired over Bluetooth. Before, a device seen once kept it
  in the bar.
- A keyboard paired twice, to a receiver and over Bluetooth, no longer shows
  a second row while both links are asleep.

## 1.0.4

- The "Live updates are broken" message clears as soon as the live monitor
  recovers, for example after Solaar is installed. The monitor now reports once
  that it is listening, instead of staying silent until a device links or
  unlinks.

Thanks to Ramon Cardena (ramoncardena) for the report and the fix.

## 1.0.3

- A Bluetooth device read before it has a real serial no longer leaves ghost
  rows. An all-zero serial, or a fallback path-and-slot id, is not kept as an
  extra asleep copy once the real serial answers.
- When the same id is online on one connection and asleep on another, the
  panel shows only the online one. The asleep link stays paired and shows
  again when it is the one that is up.
- Backlight for a directly connected device is sent by its name, so it reaches
  the online keyboard instead of an asleep receiver slot with the same serial.

Thanks to Thibaut Maurras (Foufou-exe) for the Bluetooth ghost-row fix.

## 1.0.2

- Turning a keyboard's backlight on from the bulb, or by right-clicking the
  bar icon, works again. Solaar was told `1`, which on 1.1.20 is looked up as
  a choice value rather than a position and then crashes; switching off
  (`highest`) was never affected. The on path now sends `lowest`, the same
  first choice in value order.
- A keyboard or mouse that was unpaired, or re-paired into another slot under
  a new id, no longer stays in the panel forever as asleep, including across
  restarts. When a receiver's pairings were all read, a remembered device it
  no longer holds is dropped, along with its low-battery flag. One whose
  receiver was unplugged, or failed to list, is still kept as asleep.

Thanks to Clayton Faria (claytonfaria) for both fixes.

## 1.0.1

- Security: the status helper no longer falls back to a lock file at the
  predictable shared path `/tmp/solaarchy-status.lock` when `XDG_RUNTIME_DIR`
  is unset, where another local user could plant a symlink and have every
  refresh truncate a file of yours. The lock now lives only in a directory
  owned by you and closed to others (`$XDG_RUNTIME_DIR`, `/run/user/<uid>`,
  else `~/.cache/solaarchy` created as 0700). It is created exclusively
  (`O_CREAT|O_EXCL`), opened without following symlinks and without
  truncating, and refused unless it is a regular file of yours with a single
  link.

## 1.0.0

First public release.

- Battery level, charging state and a charge bar for every Logitech device that
  Solaar can see: Bolt, Unifying, Nano, Lightspeed and 27 MHz receivers, plus
  HID++ devices on USB or Bluetooth.
- Live updates without polling: a device that disconnects shows as asleep at
  once with its last reading, and one that reconnects, or a receiver plugged
  in or out, triggers a fresh read.
- Last readings are kept across shell restarts.
- One desktop notification per discharge when a device drops below the
  low-battery threshold.
- Keyboard backlight on/off from the bulb next to each keyboard's name or by
  right-clicking the bar icon, through `solaar config`, so the running Solaar
  app keeps the change.
- The widget hides itself while no receiver or device is connected (optional).
- A labelled Solaar button on the DEVICES line opens Solaar.
- Bar icon picker in its own sub-panel: a full-width Solaar button and the
  device icons in a 3 × 2 grid, filled on top and outline below.
- Your own bar icon: **+** in the picker opens a file chooser, copies the SVG
  into `~/.config/omarchy/solaarchy/icons` and selects it. Every file in that
  folder is a tile of its own, drawn in the theme's bar colour like the
  built-ins, so a vendor mark stays the user's own file. Solaarchy ships no
  vendor logos.
- Device icons from Material Symbols: mouse, keyboard and keyboard + mouse,
  filled and outline, all with one stroke weight.
- A device that goes offline or can't be read keeps its last known name,
  kind and reading, dimmed as stale, instead of disappearing.
- If the connection watcher can't start, the panel says so.
- Reliable readings next to the Solaar app: reads are serialized, every HID++
  feature lookup is double-checked so another program's reply is never taken
  as a battery level, and Solaar's configuration file is never written.
