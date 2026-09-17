import QtQuick
import QtQml
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "icons.js" as Icons

// Solaarchy: Logitech devices in the Omarchy bar, through Solaar.
//
// The bar entry point owns the device state; Panel.qml only draws it.
//
// Everything goes through Solaar, which grants hidraw access with its own
// udev rule, so this plugin adds no udev rule, no system service and no
// hand-rolled HID++ writes:
//   - solaarchy-status.py reads battery and backlight with Solaar's library
//   - solaarchy-monitor.py, a listen-only child of the shell, reports devices
//     connecting and disconnecting, and receivers coming and going
//   - the backlight switch runs `solaar config`, which hands the change to a
//     running Solaar GUI so it is saved and re-applied when the keyboard wakes
BarWidget {
  id: root
  moduleName: "io.github.c50nk4.solaarchy"

  // Panel lifecycle, forwarded to the loaded Panel.qml as the shell expects.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = iconButton
    panelLoader.item.hostWidget = root
  }

  readonly property color urgent: bar ? bar.urgent : Color.urgent

  readonly property string helperPath: localPath("solaarchy-status.py")
  readonly property string monitorPath: localPath("solaarchy-monitor.py")
  readonly property string iconPickerPath: localPath("solaarchy-pick-icon.py")
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 300, 60, 3600)
  readonly property int lowThreshold: intSetting("lowThreshold", 15, 5, 50)
  readonly property bool hideWhenDisconnected: boolSetting("hideWhenDisconnected", true)
  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: home + "/.local/state/omarchy/solaarchy.json"

  // Bar icon: the saved setting, or the pick just made in the panel until the
  // shell reports the setting back. Two settings back it, because `icon` is an
  // enum in the manifest and so can only ever hold a built-in id: `customIcon`
  // names a file in customIconDir and wins while it is set, which keeps the
  // Omarchy settings dropdown valid either way.
  readonly property string settingIcon: Icons.byId(String(setting("icon", Icons.defaultId))).id
  readonly property string settingCustomIcon: String(setting("customIcon", "")).trim()
  property string iconOverride: ""
  readonly property var currentIcon: resolveIcon(iconOverride !== "" ? iconOverride
    : (settingCustomIcon !== "" ? "custom:" + settingCustomIcon : settingIcon))
  onSettingIconChanged: iconOverride = ""
  onSettingCustomIconChanged: iconOverride = ""

  // Custom bar icons: every SVG in the icon folder, in name order. Solaarchy
  // ships no vendor logos, so this is how someone puts their hardware's mark
  // (or anything else) in their own bar without the plugin carrying artwork it
  // has no licence to. Any number of files can sit there, so switching between
  // them is one click in the picker.
  readonly property string customIconDir: {
    var dir = String(setting("customIconDir", "")).trim()
    if (dir === "") dir = home + "/.config/omarchy/solaarchy/icons"
    return dir.replace(/\/+$/, "")
  }
  // File name (without .svg) -> { aspect, source }, filled in as each file is
  // read: its own proportions, and the drawing repainted flat white so the bar
  // can tint it to the theme colour (see Icons.flattenSvg).
  property var customArt: ({})
  // Shown on the picker page when adding an icon failed; cleared on the next try.
  property string iconPickError: ""
  readonly property var customIcons: {
    var out = []
    for (var i = 0; i < customIconFiles.count; i++) {
      var file = String(customIconFiles.get(i, "fileName"))
      var name = file.replace(/\.svg$/i, "")
      var art = customArt[name]
      // Until the file has been read, draw it straight from disk: the right
      // shape in its own colours for a frame or two, rather than a gap.
      out.push(Icons.custom(name, art ? art.source : "file://" + customIconDir + "/" + file,
                            art ? art.aspect : 0))
    }
    return out
  }

  // Devices as last reported, merged with what was seen before: a sleeping
  // device keeps its last battery reading (flagged stale) instead of vanishing.
  // The list is saved to statePath, so that also survives a shell restart.
  property var devices: []
  property var receivers: []
  // Device ids already warned about. An id is dropped once a fresh reading
  // shows that device charging or back above the threshold.
  property var lowNotified: ({})
  property string savedText: ""
  // Signature of the last published `devices`, battery.readAt excluded (see
  // deviceSignature()). Lets applyStatus() skip reassigning `devices` on a
  // read that changed nothing rendered, so PanelContent.qml's Repeater isn't
  // torn down and rebuilt (every device's icon Shape included) on every
  // unchanged poll — most of them, once a desk's devices settle.
  property string lastDeviceSignature: ""
  property string lastError: ""
  // Partial failures from the last read (e.g. one receiver would not open)
  // while other devices were still read fine.
  property var warnings: []
  property string actionError: ""
  // Set when solaarchy-monitor.py reports its own startup failure (e.g. no
  // pyudev). It keeps getting relaunched every 60s regardless, so this is
  // the only way the user finds out live connect/disconnect updates are
  // broken and the widget has silently fallen back to poll-only.
  property string monitorError: ""
  property double lastUpdated: 0
  property bool loaded: false
  property int nowTick: 0

  // Device id -> 0/1 while a backlight switch to off/on is in flight
  // (optimistic UI); empty when idle.
  property var pendingBacklight: ({})
  property bool refreshQueued: false

  readonly property bool refreshing: statusProc.running
  readonly property bool backlightBusy: backlightProc.running

  // The first device with a backlight; right-clicking the bar icon toggles it.
  readonly property var keyboard: {
    for (var i = 0; i < devices.length; i++)
      if (devices[i].backlight) return devices[i]
    return null
  }

  // A fresh, currently-connected reading — the same predicate
  // checkLowBattery() uses, so a stale or offline reading never drives a
  // notification, the bar icon's urgent color, or a panel row's urgent color.
  function isLive(d) { return !d.stale && d.online }

  // Mark a device entry as no longer being read, keeping whatever battery
  // reading it already has (if any) but flagged stale. Mutates and returns d.
  function markStale(d) {
    d.online = false
    d.stale = !!d.battery
    return d
  }

  // A content fingerprint for a device list, ignoring battery.readAt: that
  // field advances on every successful read even when the reading itself
  // didn't change, which would defeat the point of comparing signatures.
  function deviceSignature(list) {
    return JSON.stringify(list, function(key, value) {
      return key === "readAt" ? undefined : value
    })
  }

  readonly property var lowest: {
    var best = null
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      var b = d.battery
      if (b && isLive(d) && (best === null || b.level < best.battery.level)) best = d
    }
    return best
  }
  readonly property bool anyLow: lowest !== null && lowest.battery.level <= lowThreshold

  // Anything Logitech to show, or an error worth showing. Before the first
  // read this comes from the saved state, so a desk without a receiver
  // doesn't flash the widget in at login.
  readonly property bool hardwarePresent: devices.length > 0 || receivers.length > 0 || lastError !== ""

  function localPath(name) {
    return decodeURIComponent(Qt.resolvedUrl(name).toString().replace(/^file:\/\//, ""))
  }

  // An icon id to its record: built-ins from icons.js, "custom:<name>" from the
  // icon folder. A custom pick whose file has since been renamed or deleted
  // falls back to the built-in icon rather than drawing nothing.
  function resolveIcon(id) {
    if (id.indexOf("custom:") !== 0) return Icons.byId(id)
    for (var i = 0; i < customIcons.length; i++)
      if (customIcons[i].id === id) return customIcons[i]
    return Icons.byId(settingIcon)
  }

  // One custom icon, as read from disk: its proportions (so a wide logo gets a
  // wide bar slot, exactly like a built-in record) and its drawing repainted
  // white, handed to the Image as a data URL. Flattening once here, rather than
  // per colour change, keeps theme switches to a GPU tint of the same texture.
  function noteCustomArt(file, svg) {
    var name = String(file).replace(/\.svg$/i, "")
    var flat = Icons.flattenSvg(svg)
    if (flat === "") return
    var art = {
      "aspect": svgAspect(svg),
      "source": "data:image/svg+xml;utf8," + encodeURIComponent(flat)
    }
    var known = customArt[name]
    if (known && known.aspect === art.aspect && known.source === art.source) return
    // A fresh object, so the bindings on customArt actually re-evaluate.
    var next = {}
    for (var key in customArt) next[key] = customArt[key]
    next[name] = art
    customArt = next
  }

  // Width/height from an SVG's viewBox, or failing that its width and height
  // attributes. 0 when neither is usable, which leaves the icon square.
  function svgAspect(svg) {
    var box = /viewBox\s*=\s*["']\s*[-\d.eE]+[,\s]+[-\d.eE]+[,\s]+([-\d.eE]+)[,\s]+([-\d.eE]+)/.exec(svg)
    if (box && parseFloat(box[1]) > 0 && parseFloat(box[2]) > 0)
      return parseFloat(box[1]) / parseFloat(box[2])
    var w = /<svg[^>]*\swidth\s*=\s*["']([\d.]+)/.exec(svg)
    var h = /<svg[^>]*\sheight\s*=\s*["']([\d.]+)/.exec(svg)
    if (w && h && parseFloat(w[1]) > 0 && parseFloat(h[1]) > 0)
      return parseFloat(w[1]) / parseFloat(h[1])
    return 0
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  // Settings can round-trip through the IPC (`omarchy bar set`, string-based)
  // as well as arrive as a native JS default, so a plain `!== false` would
  // read a stored "false" string as true. Compare textually instead.
  function boolSetting(name, fallback) {
    return String(setting(name, fallback)) !== "false"
  }

  function refresh() {
    // Asked mid-read (e.g. right after a backlight switch): that read may
    // predate the change, so run another one as soon as it ends.
    if (statusProc.running) { refreshQueued = true; return }
    statusProc.running = true
  }

  // Drop the optimistic backlight state only when no newer answer is coming:
  // not while a switch is still running, and not from a read that a queued
  // follow-up is about to supersede.
  function settleBacklight() {
    if (!backlightProc.running && !refreshQueued) pendingBacklight = ({})
  }

  function applyStatus(raw) {
    // Settle on every finished read, failed ones included, so a failed read
    // can't leave the switch stuck on a state that was never confirmed.
    settleBacklight()

    var lines = String(raw || "").trim().split("\n")
    var doc = null
    try {
      doc = JSON.parse(lines[lines.length - 1])
    } catch (e) {
      lastError = "Could not read device status"
      return
    }
    // Presence, not truthiness: a caught exception can stringify to "",
    // which a plain `if (doc.error)` would miss and fall through on.
    if (doc.error !== undefined) {
      lastError = String(doc.error)
      return
    }
    warnings = Array.isArray(doc.warnings) ? doc.warnings.map(String) : []

    var previous = {}
    for (var i = 0; i < devices.length; i++) previous[devices[i].id] = devices[i]

    var now = Date.now()
    var merged = []
    var incoming = doc.devices || []
    for (var j = 0; j < incoming.length; j++) {
      var d = incoming[j]
      var old = previous[d.id]
      if (old) delete previous[d.id]
      d.stale = false
      if (d.battery) d.battery.readAt = now
      if (!d.online && old) {
        // An unreachable device can't be asked for its name or type at all
        // (unlike Solaar's own "Unknown device <wpid>"/"?" fallbacks, which
        // are just as easy to keep instead of pattern-matching for).
        if (old.name) { d.name = old.name; d.fullName = old.fullName }
        if (old.kind) d.kind = old.kind
      }
      // A device we've seen before that came back without a battery or
      // backlight reading this time — asleep, its receiver busy with
      // another program, a detected HID++ reply race (d.busy), or just one
      // of two independent transient read failures on this pass — keeps
      // its last good values, flagged stale so they never notify.
      if (old) {
        if (!d.battery && old.battery) { d.battery = old.battery; d.stale = true }
        if (!d.backlight && old.backlight) d.backlight = old.backlight
      }
      merged.push(d)
    }
    // A device can be missing from this read entirely rather than merely
    // reported offline (e.g. its whole receiver was unplugged, so it was
    // never enumerated at all this round): keep its last known reading
    // instead of dropping it, exactly like a device that is merely asleep.
    for (var leftoverId in previous) {
      merged.push(markStale(Object.assign({}, previous[leftoverId])))
    }

    // Same idea for receivers: don't drop one this read didn't list while a
    // device that belongs to it is still being shown (stale or not).
    var mergedReceivers = Array.isArray(doc.receivers) ? doc.receivers.map(String) : []
    var receiverSet = {}
    for (var r = 0; r < mergedReceivers.length; r++) receiverSet[mergedReceivers[r]] = true
    for (var m = 0; m < merged.length; m++) {
      var rv = merged[m].receiver
      if (rv && !receiverSet[rv]) { receiverSet[rv] = true; mergedReceivers.push(rv) }
    }
    receivers = mergedReceivers

    var sig = deviceSignature(merged)
    if (sig === lastDeviceSignature) {
      // Nothing rendered actually changed: patch each device's freshest
      // readAt in place (by id, since merge order isn't guaranteed stable)
      // instead of publishing a new array, so "read X ago" is still correct
      // whenever this device eventually does go stale, without forcing a
      // Repeater rebuild for a read that changed nothing on screen.
      var freshById = {}
      for (var f = 0; f < merged.length; f++) freshById[merged[f].id] = merged[f]
      for (var k = 0; k < devices.length; k++) {
        var fresh = freshById[devices[k].id]
        if (devices[k].battery && fresh && fresh.battery) devices[k].battery.readAt = fresh.battery.readAt
      }
    } else {
      devices = merged
      lastDeviceSignature = sig
    }
    lastError = ""
    lastUpdated = now
    loaded = true
    checkLowBattery()
    saveState()
  }

  // Warn once per discharge. Only fresh readings count: a stale reading from
  // a sleeping device neither warns nor clears the warning.
  function checkLowBattery() {
    var next = Object.assign({}, lowNotified)
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      var b = d.battery
      if (!b || !isLive(d)) continue
      if (b.level <= lowThreshold && !b.charging && !b.full) {
        if (!next[d.id]) {
          next[d.id] = true
          notifyLow(d)
        }
      } else {
        delete next[d.id]
      }
    }
    lowNotified = next
  }

  // Freedesktop icon-theme names for notify-send, not the Nerd Font glyphs
  // kindIcon() returns for on-screen text — the two are different namespaces.
  function notifyIcon(kind) {
    if (kind === "keyboard") return "input-keyboard"
    if (kind === "mouse" || kind === "trackball" || kind === "touchpad") return "input-mouse"
    if (kind === "headset") return "audio-headset"
    return "input-mouse"
  }

  function notifyLow(device) {
    var icon = notifyIcon(device.kind)
    // A real app name keeps it in notification history; plain notify-send
    // would count as throwaway.
    Util.execArgv(["notify-send", "-a", "Solaarchy", "-i", icon,
      device.name + " battery low",
      device.battery.level + "% left. Charge it soon."])
  }

  function saveState() {
    var text = JSON.stringify({
      version: 1,
      receivers: receivers,
      devices: devices,
      lowNotified: lowNotified
    }) + "\n"
    if (text === savedText) return
    savedText = text
    stateFile.setText(text)
  }

  // Seeds the panel with the saved readings until the first live read lands.
  function loadState(raw) {
    var doc = null
    try { doc = JSON.parse(raw) } catch (e) { return }
    if (!Util.isPlainObject(doc)) return
    savedText = raw
    if (Util.isPlainObject(doc.lowNotified))
      lowNotified = Object.assign({}, doc.lowNotified, lowNotified)
    if (loaded || !Array.isArray(doc.devices)) return
    if (Array.isArray(doc.receivers)) receivers = doc.receivers.map(String)
    var restored = []
    for (var i = 0; i < doc.devices.length; i++) {
      var d = doc.devices[i]
      if (!Util.isPlainObject(d) || !d.id) continue
      restored.push(markStale(d))
    }
    devices = restored
  }

  // solaarchy-monitor.py reports links dropping and coming back as they happen.
  function handleMonitorLine(line) {
    var ev = null
    try { ev = JSON.parse(line) } catch (e) { return }
    if (ev.event === "error") { monitorError = String(ev.error || "monitor failed"); return }
    monitorError = ""
    if (ev.event === "link" && !ev.online && markOffline(ev.path, ev.number)) return
    if (ev.event === "link" || ev.event === "hotplug") eventRefresh.restart()
  }

  // A disconnect needs no read: the event already says the device is gone,
  // and asking the receiver would only confirm it seconds later.
  function markOffline(path, number) {
    var found = false
    var next = devices.map(function(d) {
      if (d.path !== path || d.number !== number) return d
      found = true
      return markStale(Object.assign({}, d))
    })
    if (!found) return false
    devices = next
    // A read already under way may have pinged before the link dropped.
    if (statusProc.running) refreshQueued = true
    saveState()
    return true
  }

  function backlightOn(device) {
    if (!device || !device.backlight) return false
    var pending = pendingBacklight[device.id]
    return pending !== undefined ? pending === 1 : !!device.backlight.enabled
  }

  function backlightBusyFor(device) {
    return backlightProc.running && !!device && pendingBacklight[device.id] !== undefined
  }

  function toggleBacklight(device) {
    device = device || keyboard
    if (!device || !device.backlight || backlightProc.running) return
    var target = backlightOn(device) ? 0 : 1
    var next = Object.assign({}, pendingBacklight)
    next[device.id] = target
    pendingBacklight = next
    actionError = ""
    // Solaar lists a keyboard's backlight choices sorted by value, and their
    // names are translated and differ per model ("Enabled", "Automatic",
    // "Manual"). Disabled is always the highest value and choice 1 is always
    // an "on" mode, so pick by position instead of by name.
    // sh -c exec: a missing binary is sh exiting 127, never a failed start
    // inside the shell process.
    backlightProc.command = ["/bin/sh", "-c", 'exec "$0" "$@"', "solaar", "config",
      String(device.id), "backlight", target === 1 ? "1" : "highest"]
    backlightProc.running = true
  }

  function openSolaar() {
    // A running Solaar is a GApplication: a second launch just raises its window.
    Util.execArgv(["uwsm-app", "--", "solaar"])
    close()
  }

  // The "+" tile in the picker: a native file dialog, and whatever is chosen is
  // copied into the icon folder and selected. Dropping a file in the folder by
  // hand does the same thing; this is the version that needs no terminal.
  function pickCustomIcon() {
    if (iconPickProc.running) return
    iconPickError = ""
    iconPickProc.running = true
  }

  // FolderListModel only watches a folder that existed when it was pointed at
  // one, and the helper creates it on the first pick; re-pointing it is what
  // makes that first icon show up without a shell restart.
  function rescanCustomIcons() {
    var folder = customIconFiles.folder
    customIconFiles.folder = ""
    customIconFiles.folder = folder
  }

  function chooseIcon(id) {
    iconOverride = id
    // Stored like any widget setting, so the Omarchy settings UI shows it too.
    // A custom pick only writes the file name; picking a built-in also clears
    // it, since customIcon is what decides which of the two is drawn.
    var custom = id.indexOf("custom:") === 0
    Util.execArgv(["omarchy", "bar", "set", root.moduleName, "customIcon",
                   custom ? id.substring("custom:".length) : ""])
    if (!custom) Util.execArgv(["omarchy", "bar", "set", root.moduleName, "icon", id])
  }

  function kindIcon(kind) {
    if (kind === "keyboard") return "󰌌"
    if (kind === "mouse" || kind === "trackball" || kind === "touchpad") return "󰍽"
    if (kind === "headset") return "󰋋"
    return "󰂑"
  }

  function percentText(device) {
    if (!device.battery) return "—"
    return (device.battery.approximate ? "~" : "") + device.battery.level + "%"
  }

  function statusText(device) {
    var b = device.battery
    if (!device.online) {
      if (!b) return loaded ? "Asleep" : "Not read yet"
      var when = b.readAt ? agoText(b.readAt) : "earlier"
      return (loaded ? "Asleep · read " : "Last reading · ") + when
    }
    if (!b) return "No battery info"
    if (b.full) return "Fully charged"
    if (b.charging) return "Charging"
    if (b.level <= lowThreshold) return "Low battery"
    return "On battery"
  }

  function agoText(timestamp) {
    nowTick // re-evaluate on the ticker
    var s = Math.max(0, Math.round((Date.now() - timestamp) / 1000))
    if (s < 60) return "just now"
    var m = Math.round(s / 60)
    if (m < 60) return m + " min ago"
    var h = Math.round(m / 60)
    if (h < 48) return h + " h ago"
    return Math.round(h / 24) + " d ago"
  }

  function ageText() {
    return lastUpdated ? agoText(lastUpdated) : ""
  }

  readonly property string metaText: {
    if (refreshing && !loaded) return "Reading devices…"
    if (lastError !== "" && !loaded) return "Unavailable"
    var parts = [devices.length === 1 ? "1 device" : devices.length + " devices"]
    var age = ageText()
    if (refreshing) parts.push("reading…")
    else if (age !== "") parts.push(age)
    return parts.join(" · ")
  }

  readonly property string barTooltip: {
    if (!loaded) return lastError !== "" ? "Solaarchy: " + lastError : "Solaarchy: reading devices…"
    var parts = []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      parts.push(d.name + " " + percentText(d) + (d.battery && d.battery.charging ? " ⚡" : ""))
    }
    if (keyboard) parts.push("Backlight " + (backlightOn(keyboard) ? "on" : "off") + " (right-click)")
    return parts.length > 0 ? parts.join("\n") : "No Logitech devices found"
  }

  onOpenedChanged: {
    if (!opened) return
    actionError = ""
    // Reading wakes the receiver and takes seconds; don't redo a fresh one.
    if (Date.now() - lastUpdated > 30000) refresh()
  }

  // Hidden like the stock power widget on a desktop: the bar gives the slot
  // back, and the listener brings it back when a receiver is plugged in.
  visible: !hideWhenDisconnected || hardwarePresent
  onVisibleChanged: if (!visible) close()
  onBarChanged: injectPanel()

  implicitWidth: iconButton.implicitWidth
  implicitHeight: iconButton.implicitHeight

  Process {
    id: statusProc
    command: ["/usr/bin/python3", root.helperPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onExited: {
      if (!root.refreshQueued) return
      root.refreshQueued = false
      Qt.callLater(root.refresh)
    }
  }

  // The helper arms its own 20 s alarm, but that resets to a fresh 20 s once
  // the read's own flock is acquired, so a legitimately busy (not wedged)
  // helper can legally run for just under 40 s; give this belt more room
  // than that so it only ever fires on a truly wedged python.
  Timer {
    interval: 45000
    running: statusProc.running
    onTriggered: {
      statusProc.running = false
      root.lastError = "Timed out reading devices"
      root.settleBacklight()
    }
  }

  // Coalesces bursts (several devices waking together, a receiver replugged)
  // and gives a just-connected device a moment before it is asked anything.
  Timer {
    id: eventRefresh
    interval: 2500
    onTriggered: root.refresh()
  }

  Process {
    id: monitorProc
    // pdeathsig: the kernel stops the listener with the shell, however it exits.
    command: ["setpriv", "--pdeathsig", "TERM", "/usr/bin/python3", root.monitorPath]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.handleMonitorLine(line) }
    }
    onExited: monitorRestart.start()
  }

  Timer {
    id: monitorRestart
    interval: 60000
    onTriggered: monitorProc.running = true
  }

  FileView {
    id: stateFile
    path: root.statePath
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
  }

  Process {
    id: backlightProc
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.pendingBacklight = ({})
        root.actionError = exitCode === 127 ? "solaar is not installed" : "Could not switch the backlight"
      }
      root.refresh()
    }
  }

  // `solaar config` has no timeout of its own; if the device is unreachable
  // mid-write this is what clears the optimistic pendingBacklight state
  // instead of leaving the bulb stuck disabled until the shell restarts.
  Timer {
    interval: 20000
    running: backlightProc.running
    onTriggered: {
      backlightProc.running = false
      root.pendingBacklight = ({})
      root.actionError = "Timed out switching the backlight"
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // Keeps every "X ago" text fresh, including the bar icon's hover tooltip
  // (barTooltip), which is reachable without the panel ever being opened —
  // this can't be scoped to root.opened the way the panel-only redraws are.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowTick++
  }

  Component.onCompleted: refresh()

  // The file dialog for the "+" tile. Exit 0 prints the installed file's name,
  // 1 means the dialog was cancelled, 2 prints why it failed on stderr.
  Process {
    id: iconPickProc
    command: ["/usr/bin/python3", root.iconPickerPath, root.customIconDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = text.trim()
        if (name === "") return
        root.rescanCustomIcons()
        root.chooseIcon("custom:" + name)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = text.trim()
        if (message !== "") root.iconPickError = message
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 127) root.iconPickError = "Could not start the file chooser"
    }
  }

  // The icon folder, watched so a file dropped in or taken out shows up in the
  // picker without a shell restart. A missing folder is simply empty.
  FolderListModel {
    id: customIconFiles
    folder: "file://" + root.customIconDir
    nameFilters: ["*.svg"]
    showDirs: false
    showHidden: false
    sortField: FolderListModel.Name
  }

  // One reader per file, for the viewBox only: the drawing itself is rendered
  // from the file by IconMark.
  Instantiator {
    model: customIconFiles
    delegate: FileView {
      required property string fileName
      path: root.customIconDir + "/" + fileName
      watchChanges: true
      printErrors: false
      onLoaded: root.noteCustomArt(fileName, text())
    }
  }

  BarIconButton {
    id: iconButton
    anchors.fill: parent
    bar: root.bar

    readonly property real markHeight: Icons.scaledHeight(root.currentIcon, Style.bar.iconCanvas)
    readonly property real markWidth: markHeight * root.currentIcon.width / root.currentIcon.height

    // Wordmarks are wider than a glyph slot; widen the slot instead of
    // letting them spill over the neighbouring widgets.
    slotSize: Math.max(Style.bar.iconSlot, markWidth + Style.space(10))
    iconComponent: markComponent
    foreground: root.anyLow ? root.urgent : (root.bar ? root.bar.barForeground : Color.foreground)
    dimmed: !root.loaded
    tooltipText: root.barTooltip
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleBacklight()
      else if (b === Qt.MiddleButton) root.openSolaar()
      else root.toggle()
    }

    // The wrapper Item takes the Loader's forced square size so the mark
    // keeps its own width.
    Component {
      id: markComponent
      Item {
        IconMark {
          anchors.centerIn: parent
          iconId: root.currentIcon.id
          iconData: root.currentIcon.custom ? root.currentIcon : null
          height: iconButton.markHeight
          // No colour animation, like the stock glyph icons: the bar already
          // animates its foreground, and bars that recolour widgets with a
          // shader match against that foreground exactly.
          color: iconButton.foreground
        }
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
