---
name: solaarchy-addon
description: Write, test or fix an add-on for Solaarchy, the Omarchy bar widget for Logitech devices. An add-on is an Omarchy plugin with a solaarchy-addon.json that puts its controls into a device's drawer in Solaarchy's panel, or opens its own panel for that device; a built-in one lives in Solaarchy's addons/ folder. Use whenever someone wants haptics, lighting, buttons, DPI or other per-device controls for a Logitech device in Solaarchy, wants to scaffold an add-on, has one that doesn't show up, or wants one curated.
---

# Solaarchy add-on

The reference is `addons/ADDONS.md` in Solaarchy's repository. Installed
copy: `~/.config/omarchy/plugins/io.github.c50nk4.solaarchy/addons/ADDONS.md`.
Read it before writing code; this skill is the workflow around it.

## 1. Pick the kind

- **External add-on** (the default): its own Omarchy plugin and its own
  repository. It gets the public drawer API, `device` and `host`, and its
  controls are mouse only.
- **Built-in add-on**: a folder in Solaarchy's `addons/`, shipped to every
  Solaarchy user. Only for something most owners of that hardware want, and
  only with the maintainer's agreement. Solaarchy stays small. Skip to
  [Built-in](#built-in).

## 2. Check the device first

- `solaar show` lists each device's features and settings. The add-on's
  `features` are those Solaar feature names. The category table is in
  ADDONS.md.
- Every device access goes through Solaar and takes Solaarchy's lock:

  ```sh
  flock "$XDG_RUNTIME_DIR/solaarchy-status.lock" solaar config "$selector" <setting> <value>
  ```

  No raw HID++ writes and no udev rule of its own. Only touch features the
  device lists in `device.features`.
- No device to test on? Say so, and keep the add-on read-only until someone
  with the hardware tries it.

## 3. Scaffold an external add-on

Put the folder in `~/.config/omarchy/plugins/<folder>/`. Omarchy needs a kind
before it can enable a plugin. A drawer-only add-on uses `service`; one with a
floating panel uses `panel` (see ADDONS.md, "Floating panel").

`manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "io.github.<you>.<name>",
  "name": "<Name>",
  "version": "0.1.0",
  "author": "<you>",
  "description": "<What it adds to Solaarchy's device drawer>",
  "kinds": ["service"],
  "entryPoints": { "service": "Service.qml" }
}
```

`Service.qml`, which does nothing; it only gives Omarchy a kind to enable:

```qml
import QtQuick

Item {
  property var shell: null
}
```

`solaarchy-addon.json`:

```json
{
  "api": 1,
  "category": "lighting",
  "features": ["BACKLIGHT2"],
  "label": "<Name>",
  "icon": "",
  "drawer": "Drawer.qml"
}
```

`Drawer.qml`:

```qml
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Column {
  id: root
  property var device   // id, name, kind, online, selector, features
  property var host     // api, foreground, dim, urgent, fontFamily, lockPath, openPanel(extra), refresh()

  width: parent ? parent.width : 0
  spacing: Style.space(6)

  Text {
    width: parent.width
    wrapMode: Text.Wrap
    text: "<What this does for " + root.device.name + ">"
    color: root.host.dim
    font.family: root.host.fontFamily
    font.pixelSize: Style.font.caption
  }

  Button {
    text: "<Action>"
    enabled: root.device.online && !write.running
    foreground: root.host.foreground
    fontFamily: root.host.fontFamily
    onClicked: write.running = true
  }

  // Solaarchy's lock around every device access.
  Process {
    id: write
    command: ["flock", root.host.lockPath, "solaar", "config", root.device.selector, "<setting>", "<value>"]
    onExited: function(code) { if (code === 0) root.host.refresh() }
  }
}
```

`addons/rainbow/Drawer.qml` in Solaarchy is a complete drawer that uses only
this API.

## 4. Test

```sh
omarchy plugin validate ~/.config/omarchy/plugins/<folder>
/usr/bin/python3 ~/.config/omarchy/plugins/io.github.c50nk4.solaarchy/solaarchy-addons.py | jq
omarchy-shell shell rescanPlugins
omarchy plugin enable <id>
```

- **Listed?** `solaarchy-addons.py` must list the add-on with no entry in
  `errors`. Its error text names the problem: api, category, drawer path, or
  manifest id.
- **In the drawer?** Open Solaarchy's panel and click a device's chevron. The
  add-on shows in its category's section on devices with one of its
  `features`. Installed but disabled, it shows only "turned off in Omarchy's
  plugins".
- **"could not load its drawer"**: a QML error. Read it in
  `qs log -p "$OMARCHY_PATH/shell" --tail 100`.
- Saving under `~/.config/omarchy/plugins/` reloads plugin code. If the
  drawer still shows the old version, run `omarchy restart shell`. That
  restart flickers the whole desktop bar, so say so before running it.
- Test a panel without Solaarchy:
  `omarchy-shell shell summon <id> '{"device": {"id": "X", "selector": "X"}}'`.

## 5. Rules that bite

- The drawer item is rebuilt on every new battery reading. Keep state in the
  plugin's service or its helper, never in the drawer item.
- Width follows the drawer. Size the height with `implicitHeight`.
- Colours and font come from `host`, so the add-on follows the theme.
- A changed device setting needs `host.refresh()` so Solaarchy reads it again.

## 6. Get it curated

Open an issue at https://github.com/C50NK4/Solaarchy/issues with the plugin
id, the repository URL and, if there is one, its plugins.omarchy.org page.
Curated add-ons are listed in Solaarchy's Settings, with links, before anyone
installs them.

## Built-in

Follow "Built-in add-ons" in ADDONS.md: the extra keys (`setting`, `service`,
`page`, `description`, `experimental`), the service contract, the action
names, and the steps to add one (`builtinIds` in `BarWidget.qml`, and the
setting in `manifest.json`). Models to copy from:

- `addons/circadian/`: a service, a page, a drawer row in the keyboard cursor,
  and a Python helper
- `addons/rainbow/`: a drawer only, off by default, experimental

Then run `omarchy plugin validate .` in the repository, restart the shell,
and check Settings, a drawer, its page, and the keys. Its default goes in two
places, `default` in its solaarchy-addon.json and the manifest's `defaults`
and `schema`. Keep it off unless it should be on for everyone, as Circadian
is.
