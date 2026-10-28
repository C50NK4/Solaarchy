# Changelog

## 1.1.0

- Devices with per-zone LED effects (Logitech G mice such as the G403) get
  their zones in the panel: a master switch for LED Control, and per zone its
  label, its current effect and a cycler that walks the effects the firmware
  advertises (Disabled, Static, Cycle, Breathe, …). Cycling sends the effect
  with its defaults plus any param the current effect still sets, so a custom
  Cycle period survives a trip away and back, and an effect's color falls
  back to white instead of the black Solaar's own dialog would leave.
- The switches write through `solaar config`, so the running Solaar GUI
  records the change and re-applies it when the device wakes.

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
