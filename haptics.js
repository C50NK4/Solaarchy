.pragma library

// HID++ 0x19B0 haptic waveforms: the setting name (also what
// `solaarchy-haptics.py play` takes), the label drawn on its tile, and the
// id the device knows it by. A device reports which ids it has; the MX
// Master 4 has all of these. Kept in step with WAVEFORMS in
// solaarchy-haptics.py.
var waveforms = [
  { "key": "sharp-state-change", "label": "Sharp change", "id": 0x00 },
  { "key": "damp-state-change", "label": "Damp change", "id": 0x01 },
  { "key": "sharp-collision", "label": "Sharp collision", "id": 0x02 },
  { "key": "damp-collision", "label": "Damp collision", "id": 0x03 },
  { "key": "subtle-collision", "label": "Subtle collision", "id": 0x04 },
  { "key": "whisper-collision", "label": "Whisper", "id": 0x1B },
  { "key": "happy-alert", "label": "Happy alert", "id": 0x05 },
  { "key": "angry-alert", "label": "Angry alert", "id": 0x06 },
  { "key": "completed", "label": "Completed", "id": 0x07 },
  { "key": "knock", "label": "Knock", "id": 0x0C },
  { "key": "square", "label": "Square", "id": 0x08 },
  { "key": "wave", "label": "Wave", "id": 0x09 },
  { "key": "firework", "label": "Firework", "id": 0x0A },
  { "key": "mad", "label": "Mad", "id": 0x0B },
  { "key": "jingle", "label": "Jingle", "id": 0x0D },
  { "key": "ringing", "label": "Ringing", "id": 0x0E }
]

// The level buttons. Solaar's own steps for devices that only take four
// levels, and the same five points for those that take any level, so every
// device gets one control.
var levels = [
  { "value": 0, "label": "Off" },
  { "value": 25, "label": "Low" },
  { "value": 50, "label": "Med" },
  { "value": 75, "label": "High" },
  { "value": 100, "label": "Max" }
]

function byKey(key) {
  for (var i = 0; i < waveforms.length; i++)
    if (waveforms[i].key === key) return waveforms[i]
  return null
}

// The waveforms a device's reading says it can play, in tile order. A
// device that reported none gets the whole list rather than an empty page.
function forDevice(haptics) {
  var ids = haptics && Array.isArray(haptics.waveforms) ? haptics.waveforms : []
  if (ids.length === 0) return waveforms.slice()
  return waveforms.filter(function(w) { return ids.indexOf(w.id) !== -1 })
}

// The level button a reading lights up: the nearest of the five, so a level
// set elsewhere (45 from Solaar, say) still shows which button is closest.
function nearestLevel(level) {
  var best = levels[0]
  for (var i = 1; i < levels.length; i++)
    if (Math.abs(levels[i].value - level) < Math.abs(best.value - level)) best = levels[i]
  return best.value
}

// Every event Solaarchy can buzz on, in the order the haptics page lists them:
// the setting that holds its waveform, the label on its row and the tooltip
// explaining it, its group on
// the page, its default (kept in step with manifest.json), and for Hyprland
// events the socket2 names that count as it. Only the v2 form where Hyprland
// sends both, so one change is one pulse. The quiet alerts start out on; the busy
// desktop events wait to be picked.
var events = [
  { "setting": "hapticLowBattery", "label": "Low battery", "description": "Buzzes when a Logitech device (this mouse or a paired keyboard) drops below the low-battery threshold. Once per discharge.", "group": "alerts", "defaultValue": "angry-alert" },
  { "setting": "hapticUrgent", "label": "Window wants attention", "description": "Buzzes when a window that has been open a few seconds asks for attention, like a chat with a new message. Apps doing it as they launch don't count.", "group": "alerts", "defaultValue": "sharp-collision", "names": ["urgent"] },
  { "setting": "hapticBell", "label": "Terminal bell", "description": "Buzzes when something rings the system bell, usually a terminal: a finished job, or Tab with nothing to complete.", "group": "alerts", "defaultValue": "whisper-collision", "names": ["bell"] },
  { "setting": "hapticNotificationsCritical", "label": "Critical notifications", "description": "Buzzes for notifications marked critical, instead of the All notifications waveform.", "group": "alerts", "defaultValue": "sharp-state-change" },
  { "setting": "hapticNotifications", "label": "All notifications", "description": "Buzzes for every desktop notification. Per-app waveforms override this; see below.", "group": "alerts", "defaultValue": "off" },
  { "setting": "hapticScreencast", "label": "Screen sharing", "description": "Buzzes when screen sharing or recording starts, and again when it stops.", "group": "alerts", "defaultValue": "off", "names": ["screencast"] },
  { "setting": "hapticWorkspace", "label": "Workspace switch", "description": "Buzzes when you switch workspaces. A quick run of switches gives one pulse.", "group": "desktop", "defaultValue": "off", "names": ["workspacev2"] },
  { "setting": "hapticWindowOpen", "label": "Window opened", "description": "Buzzes when a new window opens.", "group": "desktop", "defaultValue": "off", "names": ["openwindow"] },
  { "setting": "hapticWindowClose", "label": "Window closed", "description": "Buzzes when a window closes.", "group": "desktop", "defaultValue": "off", "names": ["closewindow"] },
  { "setting": "hapticWindowMoved", "label": "Window moved", "description": "Buzzes when a window is sent to another workspace.", "group": "desktop", "defaultValue": "off", "names": ["movewindowv2"] },
  { "setting": "hapticFullscreen", "label": "Fullscreen", "description": "Buzzes when the focused window goes fullscreen or leaves it.", "group": "desktop", "defaultValue": "off", "names": ["fullscreen"] },
  { "setting": "hapticFloating", "label": "Floating", "description": "Buzzes when a window switches between tiled and floating.", "group": "desktop", "defaultValue": "off", "names": ["changefloatingmode"] },
  { "setting": "hapticMonitor", "label": "Monitor", "description": "Buzzes when a monitor is plugged in or unplugged.", "group": "desktop", "defaultValue": "off", "names": ["monitoraddedv2", "monitorremovedv2"] },
  { "setting": "hapticSubmap", "label": "Submap", "description": "Buzzes when you enter or leave a Hyprland keybind submap (a mode like resize).", "group": "desktop", "defaultValue": "off", "names": ["submap"] },
  { "setting": "hapticLayout", "label": "Keyboard layout", "description": "Buzzes when a physical keyboard switches to another layout.", "group": "desktop", "defaultValue": "off", "names": ["activelayout"] }
]

function inGroup(group) {
  return events.filter(function(e) { return e.group === group })
}

function eventFor(setting) {
  for (var i = 0; i < events.length; i++)
    if (events[i].setting === setting) return events[i]
  return null
}

function defaultFor(setting) {
  var e = eventFor(setting)
  return e ? e.defaultValue : "off"
}

// A waveform setting's value for display: "Off", or the waveform's label.
function labelFor(key) {
  var w = byKey(key)
  return w ? w.label : "Off"
}

// socket2 event name -> setting name.
var eventSetting = (function() {
  var map = {}
  for (var i = 0; i < events.length; i++) {
    var names = events[i].names || []
    for (var j = 0; j < names.length; j++) map[names[j]] = events[i].setting
  }
  return map
})()

// "slack=knock, spotify=off" -> { "slack": "knock", "spotify": "off" }, keys
// lowercased to match the app names notifications arrive with.
function parseAppMap(text) {
  var map = {}
  var parts = String(text || "").split(",")
  for (var i = 0; i < parts.length; i++) {
    var pair = parts[i].split("=")
    if (pair.length !== 2) continue
    var app = pair[0].trim().toLowerCase()
    var wave = pair[1].trim().toLowerCase()
    if (app !== "" && (wave === "off" || byKey(wave))) map[app] = wave
  }
  return map
}
