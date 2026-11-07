import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "events.js" as Events

// Haptics, a built-in add-on: pulses on a mouse with a haptic motor (HID++
// HAPTIC, the MX Master 4's) for the alerts and desktop events picked on its
// page, its level per device, and `haptics.py play` for scripts. While it is
// on and such a device is known, haptics.py runs as the player and keeps the
// device open, so a pulse fires at once.
//
// By @hypergol-d (PR #4), moved from Solaarchy's core into this add-on.
Item {
  id: service
  visible: false

  // Set at creation by BarWidget.qml: the widget, and this add-on's entry.
  property var host
  property var addon

  readonly property bool on: host.addonOn(addon)
  // One row per unit: the devices whose feature table has HAPTIC.
  readonly property var haptic: host.shown.filter(fits)
  readonly property bool playing: on && haptic.length > 0

  // The player's last report: device id -> {name, level, waveforms}.
  property var found: ({})
  // Device id -> level while a level write is out.
  property var pendingLevel: ({})
  // The player's last complaint (no device reachable, say), for the page.
  property string error: ""
  // An urgent line under the devices: a level write that failed.
  property string message: ""
  // The event whose waveform tiles are open on the page.
  property string expanded: ""

  function fits(device) {
    var features = host.featuresOf(device)
    return !!features && features.indexOf("HAPTIC") >= 0
  }

  // ---- Settings ----

  // An event's waveform: its setting, else its default from events.js.
  // Anything that isn't a waveform name counts as "off", so a typo in
  // `omarchy bar set` mutes the event instead of breaking it.
  function waveSetting(name) {
    var value = String(host.cfg(name, Events.defaultFor(name))).trim().toLowerCase()
    return Events.byKey(value) ? value : "off"
  }

  // Saved, and played so it can be felt while choosing.
  function setEvent(name, waveform) {
    host.saveSetting(name, waveform)
    play(waveform)
  }

  readonly property bool pauseFullscreen: host.boolSetting("hapticPauseFullscreen", false)
  readonly property string appsText: String(host.cfg("hapticNotificationApps", ""))
  readonly property var notificationApps: Events.parseAppMap(appsText)
  readonly property int eventsOn: Events.events.filter(function(e) { return service.waveSetting(e.setting) !== "off" }).length

  // The waveforms the picker offers: those any haptic device reported, or all
  // of them before the first report.
  readonly property var waveforms: {
    var ids = []
    for (var id in found) ids = ids.concat(found[id].waveforms || [])
    return Events.forDevice({ "waveforms": ids })
  }

  // ---- Level ----

  // The device's level: a write in flight, else the player's last reading,
  // else -1 (not read yet).
  function level(device) {
    var id = String(device.id)
    if (pendingLevel[id] !== undefined) return pendingLevel[id]
    var entry = found[id]
    return entry && entry.level !== null && entry.level !== undefined ? Number(entry.level) : -1
  }

  // Through `solaar config`, like the backlight switch, so a running Solaar
  // GUI records it and puts it back after the device sleeps. 0 is Solaar's off.
  function setLevel(device, value) {
    if (!device || levelProc.running || !device.online) return
    var next = Object.assign({}, pendingLevel)
    next[String(device.id)] = value
    pendingLevel = next
    message = ""
    levelProc.device = device
    levelProc.value = value
    levelProc.command = host.locked(["/bin/sh", "-c", 'exec "$0" "$@"', "solaar", "config",
      host.solaarDeviceArg(device), "haptic-level", String(value)])
    levelProc.running = true
  }

  Process {
    id: levelProc
    property var device: null
    property int value: 0
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        service.pendingLevel = ({})
        service.message = exitCode === 127 ? "solaar is not installed"
          : "Could not change the haptic level of " + (device ? device.name : "the device")
        return
      }
      // Read it back; pendingLevel goes once the player reports. Then one
      // pulse at the new level, so the choice can be felt.
      service.send({ "cmd": "rescan" })
      if (value > 0 && device) service.play("sharp-state-change", device.id)
    }
  }

  Timer {
    interval: 15000
    running: service.message !== ""
    onTriggered: service.message = ""
  }

  // ---- The player ----

  function send(command) {
    if (player.running) player.write(JSON.stringify(command) + "\n")
  }

  function play(waveform, deviceId) {
    if (!waveform || waveform === "off" || !playing) return
    var command = { "cmd": "play", "waveform": waveform }
    if (deviceId) command.device = String(deviceId)
    send(command)
  }

  function handleLine(line) {
    var ev = null
    try { ev = JSON.parse(line) } catch (e) { return }
    if (ev.event === "ready") {
      error = ""
      send({ "cmd": "notifications", "enabled": watchNotifications })
    } else if (ev.event === "devices") {
      var next = {}
      var list = Array.isArray(ev.devices) ? ev.devices : []
      for (var i = 0; i < list.length; i++) next[String(list[i].id)] = list[i]
      found = next
      pendingLevel = ({})
      reported = true
      onlineIds = onlineHaptic()
      if (list.length > 0) error = ""
    } else if (ev.event === "error") {
      error = String(ev.error || "haptics failed")
    } else if (ev.event === "notification") {
      handleNotification(String(ev.app || ""), Number(ev.urgency))
    }
  }

  Process {
    id: player
    // pdeathsig, as for Solaarchy's monitor: the player stops with the shell.
    command: ["setpriv", "--pdeathsig", "TERM", "/usr/bin/python3", service.addon.dir + "/haptics.py", "serve"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { service.handleLine(line) }
    }
    onExited: if (service.playing) restart.start()
  }

  Timer {
    id: restart
    interval: 10000
    onTriggered: if (service.playing) player.running = true
  }

  onPlayingChanged: {
    if (playing) player.running = true
    else { restart.stop(); player.running = false; found = ({}); reported = false }
  }
  Component.onCompleted: {
    // A snapshot, not a binding: Quickshell updates hasFullscreen from the
    // same events, so a binding would already match when fullscreenSettle compares.
    lastFullscreen = fullscreenFocused ? "1" : "0"
    if (playing) player.running = true
  }

  // The player keeps devices open: one that just came back (woke, or
  // reconnected over another link) needs finding again. Not before the
  // player's own first scan has reported.
  property bool reported: false
  property var onlineIds: []
  function onlineHaptic() {
    return haptic.filter(function(d) { return d.online }).map(function(d) { return String(d.id) })
  }
  Connections {
    target: service.host
    function onStatusApplied() {
      var ids = service.onlineHaptic()
      var before = service.onlineIds
      service.onlineIds = ids
      if (service.reported && ids.some(function(id) { return before.indexOf(id) < 0 }))
        service.send({ "cmd": "rescan" })
    }
    function onBatteryLow(device, critical) { service.play(service.waveSetting("hapticLowBattery")) }
  }

  // ---- Notifications ----

  // Only watch the session bus while some notification setting wants it.
  readonly property bool watchNotifications: playing && (
    waveSetting("hapticNotifications") !== "off"
    || waveSetting("hapticNotificationsCritical") !== "off"
    || Object.keys(notificationApps).some(function(app) { return notificationApps[app] !== "off" }))
  onWatchNotificationsChanged: send({ "cmd": "notifications", "enabled": watchNotifications })

  // Per-app choices first (an app set to "off" stays silent), then critical
  // urgency, then the setting for everything else. Solaarchy's own low-battery
  // notification already buzzes through hapticLowBattery.
  function handleNotification(app, urgency) {
    var name = app.trim().toLowerCase()
    if (name === "solaarchy") return
    var wave = notificationApps[name]
    if (wave === undefined) {
      var critical = urgency === 2 ? waveSetting("hapticNotificationsCritical") : "off"
      wave = critical !== "off" ? critical : waveSetting("hapticNotifications")
    }
    play(wave)
  }

  // ---- Hyprland ----

  // Last layout per keyboard and fullscreen state seen, to tell a real change
  // from Hyprland repeating itself.
  property var lastLayouts: ({})
  property string lastFullscreen: ""
  // Window address -> when it opened, for telling a new window's launch-time
  // request for attention from an open window asking for it later.
  property var windowOpenedAt: ({})
  readonly property int newWindowGrace: 3000
  readonly property bool fullscreenFocused: !!Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen

  Connections {
    target: Hyprland
    enabled: service.playing
    function onRawEvent(event) { service.handleHyprlandEvent(event) }
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    var key = Events.eventSetting[name]
    if (!key) return
    var data = String(event.data || "")
    if (name === "openwindow" || name === "closewindow") noteWindow(name, data.split(",")[0])
    if (name === "urgent") {
      // Plenty of apps ask for attention as their window first appears;
      // that's the window opening, which hapticWindowOpen covers. Only a
      // window that has been open a while counts. One that was open before
      // the shell started is unknown here, and counts as old.
      var opened = windowOpenedAt[data.trim()]
      if (opened !== undefined && Date.now() - opened < newWindowGrace) return
    }
    if (name === "fullscreen") {
      // A window opening or closing on a fullscreen workspace sends a run of
      // fullscreen>>0 and >>1 within a few milliseconds. Wait for it to
      // settle and buzz only if the state really changed.
      fullscreenSettle.pendingState = data.trim()
      fullscreenSettle.restart()
      return
    }
    if (name === "activelayout") {
      // Sent per keyboard on every focus change too, mostly naming the layout
      // already in use, and by virtual keyboards (an input method, a tool
      // typing for you) that flip between their own keymap and "error" on
      // every key. Only a physical keyboard moving to a new layout counts.
      var comma = data.indexOf(",")
      var keyboard = data.substring(0, comma)
      var layout = data.substring(comma + 1)
      if (keyboard.indexOf("hl-virtual-keyboard") === 0 || layout === "error") return
      var known = lastLayouts[keyboard]
      var layouts = Object.assign({}, lastLayouts)
      layouts[keyboard] = layout
      lastLayouts = layouts
      if (known === undefined || known === layout) return
    }
    // A game or a video in fullscreen: stay quiet. Going into or out of
    // fullscreen itself still buzzes, through fullscreenSettle.
    if (pauseFullscreen && fullscreenFocused && Events.eventFor(key).group === "desktop") return
    play(waveSetting(key))
  }

  function noteWindow(name, address) {
    var next = Object.assign({}, windowOpenedAt)
    if (name === "openwindow") next[address] = Date.now()
    else delete next[address]
    windowOpenedAt = next
  }

  Timer {
    id: fullscreenSettle
    property string pendingState: ""
    interval: 150
    onTriggered: {
      if (pendingState === service.lastFullscreen) return
      service.lastFullscreen = pendingState
      service.play(service.waveSetting("hapticFullscreen"))
    }
  }

  // ---- Settings row ----

  readonly property bool captionUrgent: on && error !== "" && haptic.length > 0
  readonly property string caption: captionUrgent ? error
    : haptic.length === 0 ? "Pulses on a mouse with a haptic motor. None here yet."
    : eventsText.charAt(0).toUpperCase() + eventsText.slice(1)
  readonly property string eventsText: eventsOn === 0 ? "no events picked"
    : eventsOn === 1 ? "1 event buzzes" : eventsOn + " events buzz"

  // ---- Keyboard cursor ----

  // Actions are "<add-on id>.<verb>[:<device id>]"; Panel.qml hands them to run().
  function levelActions(device) {
    return Events.levels.map(function(l) { return "haptics.level-" + l.value + ":" + device.id })
  }

  // Mirrors Page.qml, in reading order.
  readonly property var pageActions: {
    var list = ["haptics.toggle"]
    for (var i = 0; i < haptic.length; i++) list = list.concat(levelActions(haptic[i]))
    var rows = Events.inGroup("alerts").concat(Events.inGroup("desktop"))
    for (var r = 0; r < rows.length; r++) {
      list.push("haptics.event-" + rows[r].setting)
      if (rows[r].setting !== expanded) continue
      list.push("haptics.wave-off")
      for (var w = 0; w < waveforms.length; w++) list.push("haptics.wave-" + waveforms[w].key)
    }
    list.push("haptics.pause")
    return list
  }

  // Asked only while it is on, for the device whose drawer is open.
  function drawerActions(device) { return levelActions(device).concat(["addon-page:haptics"]) }

  function run(verb, device) {
    if (verb === "toggle") host.saveSetting(addon.setting, !on)
    else if (verb === "pause") host.saveSetting("hapticPauseFullscreen", !pauseFullscreen)
    else if (verb.indexOf("level-") === 0) setLevel(device, parseInt(verb.slice(6), 10))
    else if (verb.indexOf("event-") === 0) expanded = expanded === verb.slice(6) ? "" : verb.slice(6)
    else if (verb.indexOf("wave-") === 0 && expanded !== "") setEvent(expanded, verb.slice(5))
  }
}
