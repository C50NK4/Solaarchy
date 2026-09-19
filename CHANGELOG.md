# Changelog

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
