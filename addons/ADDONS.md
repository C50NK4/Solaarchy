# Solaarchy add-ons

Solaarchy stays small: battery, connections and the keyboard backlight.
Everything model-specific (haptics, lighting effects, button remapping)
belongs in an **add-on**. An add-on is an ordinary Omarchy plugin that you
install, update, enable and disable like any other, plus one file,
`solaarchy-addon.json`, next to its `manifest.json`.

Solaarchy's Settings lists add-ons in three groups:

- **Built-in add-ons** come with Solaarchy, one folder each next to this
  file, and switch on and off in Settings: Circadian (the keyboard light by
  civil twilight, on by default) and Rainbow LED (an experimental mock-up,
  off by default). See [Built-in add-ons](#built-in-add-ons).
- **Curated add-ons** have been reviewed for Solaarchy. They are listed even
  before they're installed, with links to their repository and their
  plugins.omarchy.org page, and shown greyed in the drawers they fit.
- **Other add-ons:** every other installed plugin with a
  `solaarchy-addon.json`. They show up by themselves and work the same way,
  marked as not reviewed.

An add-on can show up in two places, and may use both:

- **Inside a device's drawer.** Every device row in Solaarchy's panel has a
  chevron that opens its drawer. The drawer has a section per capability, and
  an add-on's own QML (buttons, sliders, …) goes into its section.
- **As its own floating panel.** If the plugin has a `panel` entry point,
  Solaarchy puts an "Open …" button in the drawer. The button opens that panel
  and tells it which device it is for.

> **API version 1.** It may still change until the first add-on ships. Open an
> issue if something is missing.

## solaarchy-addon.json

```json
{
  "api": 1,
  "category": "haptics",
  "features": ["HAPTIC"],
  "label": "Haptics",
  "icon": "󰕦",
  "drawer": "Drawer.qml"
}
```

| Key | Meaning |
|---|---|
| `api` | `1`. |
| `category` | The drawer section it appears in. One of `lighting`, `haptics`, `buttons`, `pointer`, `keyboard`, `easyswitch`. |
| `features` | Solaar feature names (`SupportedFeature` in Solaar's `logitech_receiver`). The add-on appears for a device that has at least one of them. If the list is empty or missing, it appears for every device with that category. |
| `label` | The name on its button and in Solaarchy's Settings. The default is the plugin's name. |
| `icon` | Optional. A Nerd Font glyph for the button. |
| `drawer` | Optional. A QML file inside the plugin folder, embedded in the drawer. |

The plugin itself needs at least one kind so that Omarchy can enable it. Use
`panel` if it has a floating panel, or `service` if it only needs a drawer and
a background part.

## Categories

Solaarchy reads each device's HID++ feature table once, then sorts the
features into these categories:

| Category | Features |
|---|---|
| `lighting` | BACKLIGHT, BACKLIGHT2, BACKLIGHT3, COLOR_LED_EFFECTS, RGB_EFFECTS, LED_CONTROL, PER_KEY_LIGHTING, PER_KEY_LIGHTING_V2, BRIGHTNESS_CONTROL |
| `haptics` | HAPTIC, FORCE_SENSING_BUTTON |
| `buttons` | REPROG_CONTROLS_V4, PERSISTENT_REMAPPABLE_ACTION, GESTURE_2, ONBOARD_PROFILES, GKEY, MKEYS, MR |
| `pointer` | ADJUSTABLE_DPI, EXTENDED_ADJUSTABLE_DPI, SMART_SHIFT, SMART_SHIFT_ENHANCED, HIRES_WHEEL, LOWRES_WHEEL, THUMB_WHEEL, VERTICAL_SCROLLING, POINTER_SPEED, REPORT_RATE, EXTENDED_ADJUSTABLE_REPORT_RATE |
| `keyboard` | FN_INVERSION, NEW_FN_INVERSION, K375S_FN_INVERSION, KEYBOARD_DISABLE_KEYS, KEYBOARD_DISABLE_BY_USAGE, MULTIPLATFORM, DUALPLATFORM, LOCK_KEY_STATE, KEYBOARD_LAYOUT, KEYBOARD_LAYOUT_2 |
| `easyswitch` | CHANGE_HOST, HOSTS_INFO |

How a category shows in the drawer:

- **Its own section** when something fills it: a built-in add-on (Lighting on
  a backlit keyboard), an installed add-on, or a curated one not installed
  yet (shown greyed).
- **Otherwise one muted line:** "Also: Buttons · Easy-Switch". That line is
  the room an add-on can fill.

## Drawer QML

```qml
import QtQuick
import qs.Commons
import qs.Ui

Column {
  property var device   // see below
  property var host     // see below

  width: parent ? parent.width : 0
  spacing: Style.space(6)

  PanelSlider {
    width: parent.width
    fillColor: host.foreground
    knobColor: host.foreground
    onReleased: function(value) { /* run your helper for device.selector */ }
  }
}
```

**`device`** is a plain object:

| Key | Meaning |
|---|---|
| `id` | Serial or unit id; stable per unit. |
| `name` | The device's name. |
| `kind` | `keyboard`, `mouse`, …, as Solaar reports it. |
| `online` | Whether it is awake now. |
| `selector` | What `solaar config` and `solaar show` accept for this device. |
| `features` | Its Solaar feature names. |

**`host`** is what Solaarchy offers:

| Member | Meaning |
|---|---|
| `api` | `1`. |
| `foreground`, `dim`, `urgent` | The panel's colours. They follow the theme. |
| `fontFamily` | The panel's font. |
| `lockPath` | The lock every device access takes (see below). |
| `openPanel(extra)` | Opens your floating panel for this device. Keys in `extra` join the payload. |
| `refresh()` | Asks Solaarchy for a fresh device read, for example after you changed something. |

`rainbow/Drawer.qml` next to this file is a complete drawer that uses only
this API.

Rules:

- **Width follows the drawer.** Size your height with `implicitHeight`.
- **Mouse only in API 1.** Solaarchy's keyboard cursor walks its own
  controls; your controls are not among them.
- **The item can be rebuilt at any time.** A new battery reading rebuilds the
  device's row. Keep state that matters in your plugin or in its helper, not
  in the drawer item.
- **A drawer that fails to load** is replaced by one line saying so. The rest
  of the panel keeps working.

## Floating panel

Write a normal `panel` entry point. Its `open(payloadJson)` receives:

```json
{"device": {"id": "DC94CE75", "name": "MX Master 4", "kind": "mouse",
            "online": true, "selector": "DC94CE75", "features": ["HAPTIC", "..."]}}
```

The payload also carries any keys you passed to `host.openPanel(extra)`.
Omarchy's own `plugins/panels/wifiqr/Panel.qml` is a good model. Solaarchy
opens your panel with:

```sh
omarchy-shell shell summon <your id> '<payload>'
```

This goes through the shell's public command line because the in-process API
only lets a plugin open its own panels. The command also works from a
terminal, which is handy while testing.

## Talking to the device

- **Go through Solaar.** Use `solaar config <selector> <setting> <value>`, or
  Solaar's Python library the way `solaarchy-status.py` does. Solaar already
  has the udev rule and the hidraw access, so neither Solaarchy nor its
  add-ons need their own.
- **Take the lock around every device access:** `flock` on `host.lockPath`
  (`$XDG_RUNTIME_DIR/solaarchy-status.lock`). Every Solaar process uses the same
  HID++ software id, so two programs talking to one device at once can pick up
  each other's replies.
  ```sh
  flock "$XDG_RUNTIME_DIR/solaarchy-status.lock" solaar config "$selector" haptic-level 60
  ```
- **Stay inside what the device lists.** Only probe features that Solaar names
  and that appear in `device.features`.

## Enabled, disabled, discovery

- **Discovery.** Solaarchy looks for
  `~/.config/omarchy/plugins/*/solaarchy-addon.json` every time its panel
  opens. Run `/usr/bin/python3 solaarchy-addons.py` from Solaarchy's folder to
  see what it finds.
- **Enabled state** comes from `omarchy-shell shell listPlugins`. The
  add-on's switch in Solaarchy's Settings runs `omarchy plugin enable <id>` or
  `omarchy plugin disable <id>`, so it is the same switch as Omarchy's.
- **An installed but disabled add-on gets nothing loaded:** no QML and no
  panel button. The drawer only says that it is turned off.

## Trust

Add-on QML runs inside the Omarchy shell process, just as every Omarchy plugin
does. Solaarchy adds no new trust. It loads QML only from plugins that you
installed and enabled.

## Built-in add-ons

Built-in add-ons ship inside Solaarchy, one folder each next to this file:

| Folder | Add-on | Parts |
|---|---|---|
| `circadian/` | Circadian: the keyboard light on at dusk, off at dawn | service, page, drawer, `twilight.py` |
| `rainbow/` | Rainbow LED: a greyed mock-up, off by default | drawer only, through the API above |

Each has the same `solaarchy-addon.json`, with these keys on top:

| Key | Meaning |
|---|---|
| `setting` | Required. Its on/off key in Solaarchy's own settings, such as `circadian`. |
| `default` | `true` to start on until it is switched off. Missing means off. |
| `description` | Its caption in Settings, unless its service gives one. |
| `experimental` | `true` keeps it out of the drawers while it is off. |
| `service` | Optional. A QML file whose root is an `Item`, created once at start. It runs for as long as the widget does. |
| `page` | Optional. A QML file for its own page in the panel, behind the chevron next to its switch. |

### Service

A service gets two properties at creation:

- **`host`** is Solaarchy's bar widget (`BarWidget.qml`), with all it has.
  The parts made for add-ons:
  - `shown`: one entry per device
  - `cfg(name, fallback)`, `boolSetting`, `intSetting`: settings, a change
    made in the panel included
  - `saveSetting(name, value, later)`, `stepSetting(...)`
  - `deviceSetting(device, key)`, `saveDeviceSetting(device, key, value)`
  - `setBacklight(device, 0 or 1, done)`, where `done(ok)` is called once
    the switch ends
  - `backlightOn(device)`, `backlightBusy`, `isLive(device)`
  - `panelPage`: the panel's page while it is open, else `""`
  - `nowTick`: counts every 30 s
  - `home`
  - `statusApplied()`: a signal after every device read
- **`addon`** is its entry: `id`, `setting`, `dir` (its folder), and the keys
  above.

Solaarchy asks a service for these, when it has them:

| Member | Used for |
|---|---|
| `caption`, `captionUrgent` | Its row in Settings |
| `message` | An urgent line under the devices, while it is not empty |
| `tooltipFor(device)` | A line in a keyboard bulb's tooltip |
| `fits(device)` | Whether its drawer row shows on a device, instead of the feature match |
| `setOn(on)` | Its switch in Settings, instead of a plain `saveSetting` |
| `pageActions` | Keyboard-cursor actions on its page, after "back" |
| `drawerActions(device)` | Keyboard-cursor actions of its drawer row |
| `run(verb, device)` | Runs its actions |

### Page and drawer

- **Page.** It gets `service`, `w` (the bar widget) and `view` (the panel) at
  creation, and is built fresh each time it opens. `import "../.."` gives it
  Solaarchy's own `PageHeader`, `OptionRow` and `Stepper`.
- **Drawer.** A built-in drawer's `host` has two more members, `service` and
  `view`, so its controls can join the keyboard cursor:
  `view.hasCursorOn(action)`, `view.runAction(action)` and
  `view.hoverAction(action, hovered)`.
- **Actions.** `<id>.<verb>` and `<id>.<verb>:<device id>` go to the
  service's `run()`, and `addon-page:<id>` opens its page.

### Adding one

1. Create `addons/<id>/` with its `solaarchy-addon.json`, including `setting`.
2. Add `<id>` to `builtinIds` in `BarWidget.qml`. The folders are read in that
   order at start.
3. Add the setting to `manifest.json`, in `defaults` and in `schema`, with
   the same default as its `default` key. Keep it off unless it should be on
   for everyone, as Circadian is.
4. Restart the shell (`omarchy restart shell`). QML is only read at start.

## Writing one with Claude Code

`skills/solaarchy-addon/`, next to this file, is a
[Claude Code](https://claude.com/claude-code) skill for writing an add-on: the
files, the API above, testing, and the rules. Link it into `~/.claude/skills/`
once, and Claude Code finds it from its next session on, in your add-on's own
repository too:

```sh
ln -s ~/.config/omarchy/plugins/io.github.c50nk4.solaarchy/addons/skills/solaarchy-addon ~/.claude/skills/
```

## Curated add-ons

| Category | Add-on | Status |
|---|---|---|
| `haptics` | Haptics for the MX Master 4 | In development as its own plugin. Shown greyed in the drawer until it ships. |

To get yours listed, open an issue on
[Solaarchy's repository](https://github.com/C50NK4/Solaarchy/issues) with its
plugin id, its repository URL and, if it has one, its plugins.omarchy.org
page. A curated entry reaches every Solaarchy user with their next plugin
update.
