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
//   - built-in add-ons live in addons/, each in its own folder (see
//     addons/ADDONS.md); Circadian runs the same backlight switch at dusk and
//     dawn
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
  readonly property string addonsPath: localPath("solaarchy-addons.py")
  // Every device access, Solaarchy's and its add-ons', takes this flock
  // (solaarchy-status.py's lock, in the runtime dir it prefers).
  readonly property string lockPath: Quickshell.env("XDG_RUNTIME_DIR") + "/solaarchy-status.lock"
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 300, 60, 3600)
  readonly property int lowThreshold: intSetting("lowThreshold", 15, 5, 50)
  readonly property bool hideWhenDisconnected: boolSetting("hideWhenDisconnected", true)
  readonly property bool notifyLowBattery: boolSetting("notifyLowBattery", true)
  readonly property bool notifyCritical: boolSetting("notifyCritical", true)
  readonly property bool notifyConnection: boolSetting("notifyConnection", false)
  readonly property int criticalLevel: 5
  // Asleep and switched off look the same, so a device is announced as gone
  // only after this long without a live link.
  readonly property int goneAfterMs: 300000
  // Per-device choices by device id, from each device's drawer, built-in
  // add-ons' included: {"<id>": {"hidden": true, "circadian": false}}.
  readonly property var deviceSettings: {
    var all = cfg("devices", null)
    return Util.isPlainObject(all) ? all : ({})
  }
  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: home + "/.local/state/omarchy/solaarchy.json"

  // Bar icon: the saved setting, or the pick just made in the panel until the
  // shell reports the setting back. Two settings back it, because `icon` is an
  // enum in the manifest and so can only ever hold a built-in id: `customIcon`
  // names a file in customIconDir and wins while it is set, which keeps the
  // Omarchy settings dropdown valid either way.
  readonly property string settingIcon: {
    var id = String(setting("icon", Icons.defaultId))
    return Icons.isAuto(id) ? id : Icons.byId(id).id
  }
  readonly property string settingCustomIcon: String(setting("customIcon", "")).trim()
  property string iconOverride: ""
  // The pick, which the picker highlights: auto itself, not what it draws,
  // and the setting in place of a custom file that is gone (see resolveIcon).
  readonly property string chosenIcon: {
    var id = iconOverride !== "" ? iconOverride
      : (settingCustomIcon !== "" ? "custom:" + settingCustomIcon : settingIcon)
    return id.indexOf("custom:") === 0 && !resolveIcon(id).custom ? settingIcon : id
  }
  readonly property var currentIcon: resolveIcon(chosenIcon)
  onSettingIconChanged: iconOverride = ""
  onSettingCustomIconChanged: iconOverride = ""
  // What auto draws: the keyboard or the mouse when only that kind is listed,
  // else both (combo), also when neither is. Asleep devices count, so the
  // icon doesn't change each time one sleeps.
  readonly property string autoIcon: {
    var keyboards = false
    var mice = false
    for (var i = 0; i < shown.length; i++) {
      var kind = shown[i].kind
      if (kind === "keyboard" || kind === "numpad") keyboards = true
      else if (kind === "mouse" || kind === "trackball" || kind === "touchpad") mice = true
    }
    return keyboards && !mice ? "keyboard" : (mice && !keyboards ? "mouse" : "combo")
  }

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
  // One row per unit: its online link, else the link read last. The other
  // links of a unit paired twice (a receiver slot and Bluetooth) stay in
  // `devices` (and the saved state) so each can come back when it is the one
  // in use. The panel lists `shown`. A hidden device stays in `devices` too,
  // so it is still known when it comes back, but it leaves everything built
  // on `shown`.
  readonly property var shown: {
    var best = {}
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (isHidden(d)) continue
      var b = best[String(d.id)]
      if (!b || (d.online && !b.online) || (!!d.online === !!b.online && readAt(d) > readAt(b)))
        best[String(d.id)] = d
    }
    return devices.filter(function(d) { return best[String(d.id)] === d })
  }

  function readAt(d) { return d.battery && d.battery.readAt ? d.battery.readAt : 0 }
  // One entry per hidden unit, for the Settings page to bring it back.
  readonly property var hiddenDevices: {
    var seen = {}
    var out = []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!isHidden(d) || seen[String(d.id)]) continue
      seen[String(d.id)] = true
      out.push(d)
    }
    return out
  }
  property var receivers: []
  // Device ids already warned about: "low", then "critical" (true: a low
  // warning saved before the critical one existed). An id is dropped once a
  // fresh reading shows that device charging or back above the threshold.
  property var lowNotified: ({})
  // Connection notices, by unit id. offlineSince: when a device seen live
  // lost its last live link; announcedGone: devices announced as
  // disconnected, the only ones a reconnect is announced for.
  property var offlineSince: ({})
  property var announcedGone: ({})
  property var wasLive: ({})
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
  // Called with true or false when the running backlight switch ends.
  property var backlightDone: null
  property bool refreshQueued: false
  // Settings changed in the panel show at once while `omarchy bar set`
  // round-trips through shell.json; each is dropped as the shell reports it
  // back, or after a few seconds if the write never lands.
  property var pendingSettings: ({})

  readonly property bool refreshing: statusProc.running
  readonly property bool backlightBusy: backlightProc.running
  // The panel's page while it is open, else "": a built-in add-on can do
  // its work only while its page or Settings shows.
  readonly property string panelPage: opened ? String(panelLoader.item.page) : ""
  // Each read that landed, for built-in add-ons to act on.
  signal statusApplied()

  // Right-clicking the bar icon toggles this device. Prefer one that is
  // online: the same keyboard can stay paired to a receiver while it is
  // connected directly, and that asleep row still has a cached backlight.
  readonly property var keyboard: {
    var fallback = null
    for (var i = 0; i < shown.length; i++) {
      if (!shown[i].backlight) continue
      if (shown[i].online) return shown[i]
      if (!fallback) fallback = shown[i]
    }
    return fallback
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
    for (var i = 0; i < shown.length; i++) {
      var d = shown[i]
      var b = d.battery
      if (b && isLive(d) && (best === null || b.level < best.battery.level)) best = d
    }
    return best
  }
  readonly property bool anyLow: lowest !== null && lowest.battery.level <= lowThreshold

  // Anything Logitech here now, or an error worth showing: a receiver plugged
  // in, a device connected directly, or one BlueZ has paired (a Bluetooth
  // device that sleeps is gone from Solaar's view, not unpaired). The saved
  // devices don't count, or the widget would never hide again once one was
  // seen. Before the first read the saved state decides, so the widget
  // doesn't flash in or out at login.
  property bool presentNow: false
  readonly property bool hardwarePresent: lastError !== ""
    || (loaded ? presentNow : devices.length > 0 || receivers.length > 0)

  function localPath(name) {
    return decodeURIComponent(Qt.resolvedUrl(name).toString().replace(/^file:\/\//, ""))
  }

  // An icon id to its record: built-ins from icons.js, "custom:<name>" from the
  // icon folder, auto as the autoIcon of its style. A custom pick whose file
  // has since been renamed or deleted falls back to the built-in icon rather
  // than drawing nothing.
  function resolveIcon(id) {
    if (Icons.isAuto(id)) return Icons.byId(id.replace("auto", autoIcon))
    if (id.indexOf("custom:") !== 0) return Icons.byId(id)
    for (var i = 0; i < customIcons.length; i++)
      if (customIcons[i].id === id) return customIcons[i]
    return resolveIcon(settingIcon)
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
    var n = parseInt(String(cfg(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  // Settings can round-trip through the IPC (`omarchy bar set`, string-based)
  // as well as arrive as a native JS default, so a plain `!== false` would
  // read a stored "false" string as true. Compare textually instead.
  function boolSetting(name, fallback) {
    return String(cfg(name, fallback)) !== "false"
  }

  // A setting as the panel last chose it, else as shell.json has it.
  function cfg(name, fallback) {
    return pendingSettings.hasOwnProperty(name) ? pendingSettings[name] : setting(name, fallback)
  }

  // Saved like any widget setting, so the Omarchy settings UI shows it too.
  // `later` waits for the clicks to stop (steppers), so a run of them
  // rewrites shell.json once.
  function saveSetting(name, value, later) {
    var next = Object.assign({}, pendingSettings)
    next[name] = value
    pendingSettings = next
    pendingExpiry.restart()
    if (later) settingWriter.restart()
    else writeSetting(name)
  }

  function writeSetting(name) {
    Util.execArgv(["omarchy", "bar", "set", root.moduleName, name,
                   JSON.stringify(pendingSettings[name]), "--json"])
  }

  onSettingsChanged: {
    var next = {}
    var dropped = false
    for (var name in pendingSettings) {
      if (JSON.stringify(setting(name, null)) === JSON.stringify(pendingSettings[name])) dropped = true
      else next[name] = pendingSettings[name]
    }
    if (dropped) pendingSettings = next
  }

  function deviceSetting(device, key) {
    var own = deviceSettings[String(device.id)]
    return Util.isPlainObject(own) ? own[key] : undefined
  }

  // Always from the merged copy (pending included), so two quick changes to
  // different devices both survive. undefined removes the key.
  function saveDeviceSetting(device, key, value) {
    var all = JSON.parse(JSON.stringify(deviceSettings))
    var id = String(device.id)
    var own = Util.isPlainObject(all[id]) ? all[id] : {}
    if (value === undefined) delete own[key]
    else own[key] = value
    if (Object.keys(own).length > 0) all[id] = own
    else delete all[id]
    saveSetting("devices", all)
  }

  function isHidden(device) { return deviceSetting(device, "hidden") === true }

  function setHidden(device, hidden) { saveDeviceSetting(device, "hidden", hidden ? true : undefined) }

  function stepSetting(name, value, step, min, max) {
    saveSetting(name, Math.max(min, Math.min(max, value + step)), true)
  }

  // Receiver slot, or one direct hidraw node. Two links to one unit share an
  // id; matching on id alone let the Bluetooth name replace the receiver row.
  function sameLink(a, b) {
    if (!!a.receiver !== !!b.receiver || a.number !== b.number) return false
    if (a.receiver) return String(a.receiver) === String(b.receiver)
    return a.path === b.path
  }

  // False for Solaar's own stand-in when a device could not be asked its name.
  function reportedName(name) {
    var n = String(name || "").trim()
    return n !== "" && n !== "?" && n.indexOf("Unknown device") !== 0
  }

  function refresh() {
    // Asked mid-read (e.g. right after a backlight switch): that read may
    // predate the change, so run another one as soon as it ends.
    if (statusProc.running) { refreshQueued = true; return }
    // A device's feature table is read once, then kept with the device.
    var known = []
    for (var i = 0; i < devices.length; i++)
      if (devices[i].features && known.indexOf(String(devices[i].id)) < 0) known.push(String(devices[i].id))
    statusProc.command = ["/usr/bin/python3", root.helperPath, "--known=" + known.join(",")]
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
    presentNow = (Array.isArray(doc.receivers) && doc.receivers.length > 0)
      || (Array.isArray(doc.devices) && doc.devices.some(function(d) { return d && !d.receiver && d.online }))
      || Number(doc.bluetooth) > 0

    // A list, not an id map: the same id can be online on one link and asleep
    // on another, and each has to keep its own name and last reading.
    var previous = []
    var knownIds = {}
    for (var i = 0; i < devices.length; i++) {
      previous.push(devices[i])
      knownIds[String(devices[i].id)] = true
    }

    var now = Date.now()
    var merged = []
    var incoming = doc.devices || []
    for (var j = 0; j < incoming.length; j++) {
      var d = incoming[j]
      var old = null
      var oldAt = -1
      var directSameId = -1
      var directSameIdCount = 0
      var nodeAt = -1
      for (var n = 0; n < previous.length; n++) {
        var p = previous[n]
        if (!p) continue
        if (String(p.id) === String(d.id) && sameLink(p, d)) oldAt = n
        if (!d.receiver && !p.receiver && String(p.id) === String(d.id)) {
          directSameIdCount++
          directSameId = n
        }
        if (!d.receiver && !p.receiver && p.path === d.path && p.number === d.number) nodeAt = n
      }
      if (oldAt >= 0) old = previous[oldAt]
      else if (!d.receiver && directSameIdCount === 1) {
        oldAt = directSameId
        old = previous[oldAt]
      } else if (nodeAt >= 0) {
        // A directly-connected device read before its serial answered comes
        // back under a fallback id ("00000000" or path:number): it is still
        // the device already shown on that node, not a new one.
        oldAt = nodeAt
        old = previous[oldAt]
        if (!d.online) d.id = old.id
      }
      if (old) previous[oldAt] = null
      d.stale = false
      if (d.battery) d.battery.readAt = now
      if (!d.online && old) {
        // Keep the last real name only when this read has Solaar's
        // "Unknown device <wpid>"/"?" stand-in. A name this link reported
        // (the receiver's own "MX Keys Mini") stays on this link.
        if (old.name && !reportedName(d.name)) { d.name = old.name; d.fullName = old.fullName }
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
        if (!d.features && old.features) d.features = old.features
      }
      merged.push(d)
    }
    // A device can be missing from this read entirely rather than merely
    // reported offline (e.g. its whole receiver was unplugged, so it was
    // never enumerated at all this round): keep its last known reading
    // instead of dropping it, exactly like a device that is merely asleep.
    // But a device missing from a receiver that was listed in full is no
    // longer paired to it (unpaired, or re-paired elsewhere under a new id):
    // drop it, or it would show as asleep forever.
    var listed = {}
    if (Array.isArray(doc.listed))
      for (var l = 0; l < doc.listed.length; l++) listed[String(doc.listed[l])] = true
    // Hidraw node + slot of every direct device read this time: a leftover
    // direct entry on the same node is a duplicate of it under an older id.
    var directNodes = {}
    for (var dn = 0; dn < merged.length; dn++)
      if (!merged[dn].receiver && merged[dn].path) directNodes[merged[dn].path + ":" + merged[dn].number] = true
    var forgotten = false
    for (var li = 0; li < previous.length; li++) {
      var gone = previous[li]
      if (!gone) continue
      // Hiding an asleep twin leaves it in `devices`, so it is still here
      // to match the next read. Drop it only when its receiver was listed
      // in full and it was not among the pairings — that is an unpair.
      if ((gone.receiver && gone.path && listed[gone.path])
          || (!gone.receiver && directNodes[gone.path + ":" + gone.number])) {
        delete lowNotified[gone.id]
        forgotten = true
        continue
      }
      merged.push(markStale(Object.assign({}, gone)))
    }
    if (forgotten) lowNotified = Object.assign({}, lowNotified)

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
      // readAt in place (by link — two connections can share an id — since
      // merge order isn't guaranteed stable) instead of publishing a new
      // array, so "read X ago" is still correct whenever this device
      // eventually does go stale, without forcing a Repeater rebuild for a
      // read that changed nothing on screen.
      for (var k = 0; k < devices.length; k++) {
        var fresh = null
        for (var f = 0; f < merged.length; f++) {
          if (String(merged[f].id) === String(devices[k].id) && sameLink(merged[f], devices[k])) {
            fresh = merged[f]
            break
          }
        }
        if (devices[k].battery && fresh && fresh.battery) devices[k].battery.readAt = fresh.battery.readAt
      }
    } else {
      devices = merged
      lastDeviceSignature = sig
    }
    lastError = ""
    lastUpdated = now
    // Only a device paired while the shell runs is new: at login (or with no
    // saved state) every device would otherwise be announced at once.
    var paired = []
    if (loaded) {
      for (var a = 0; a < shown.length; a++)
        if (shown[a].online && !knownIds[String(shown[a].id)]) paired.push(String(shown[a].id))
    }
    loaded = true
    checkLowBattery()
    checkConnections(paired)
    saveState()
    statusApplied()
  }

  // Warn once per discharge, and once more at criticalLevel. Only fresh
  // readings count: a stale reading from a sleeping device neither warns nor
  // clears the warning.
  function checkLowBattery() {
    var next = Object.assign({}, lowNotified)
    for (var i = 0; i < shown.length; i++) {
      var d = shown[i]
      var b = d.battery
      if (!b || !isLive(d)) continue
      var draining = !b.charging && !b.full
      if (draining && b.level <= criticalLevel) {
        if (next[d.id] !== "critical") {
          // Straight past the low mark (asleep in between): one notice, not two.
          if (notifyCritical) notifyBattery(d, true)
          else if (!next[d.id] && notifyLowBattery) notifyBattery(d, false)
          next[d.id] = "critical"
        }
      } else if (draining && b.level <= lowThreshold) {
        if (!next[d.id]) {
          if (notifyLowBattery) notifyBattery(d, false)
          next[d.id] = "low"
        }
      } else {
        delete next[d.id]
      }
    }
    lowNotified = next
  }

  // By unit id, so the MX Master 4 asleep on the receiver while it is live
  // over Bluetooth counts as connected. `paired`: ids new since the last read.
  function checkConnections(paired) {
    var now = Date.now()
    var live = {}
    var names = {}
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (isHidden(d)) continue
      var id = String(d.id)
      if (!names[id] || d.online) names[id] = d
      if (d.online) live[id] = true
    }
    var since = Object.assign({}, offlineSince)
    var gone = Object.assign({}, announcedGone)
    var seen = Object.assign({}, wasLive)
    for (var key in names) {
      if (live[key]) {
        if (notifyConnection && (gone[key] || (paired && paired.indexOf(key) >= 0)))
          notifyLink(names[key], true)
        delete gone[key]
        delete since[key]
        seen[key] = true
      } else if (seen[key]) {
        if (!since[key]) since[key] = now
        else if (!gone[key] && notifyConnection && now - since[key] >= goneAfterMs) {
          gone[key] = true
          notifyLink(names[key], false)
        }
      }
    }
    offlineSince = since
    wasLive = seen
    if (JSON.stringify(gone) !== JSON.stringify(announcedGone)) {
      announcedGone = gone
      saveState()
    }
  }

  // Freedesktop icon-theme names for notify-send, not the Nerd Font glyphs
  // kindIcon() returns for on-screen text — the two are different namespaces.
  function notifyIcon(kind) {
    if (kind === "keyboard") return "input-keyboard"
    if (kind === "mouse" || kind === "trackball" || kind === "touchpad") return "input-mouse"
    if (kind === "headset") return "audio-headset"
    return "input-mouse"
  }

  // A real app name keeps these in notification history; plain notify-send
  // would count as throwaway.
  function notifyBattery(device, critical) {
    Util.execArgv(["notify-send", "-a", "Solaarchy", "-i", notifyIcon(device.kind),
      "-u", critical ? "critical" : "normal",
      device.name + (critical ? " battery critical" : " battery low"),
      device.battery.level + "% left. Charge it " + (critical ? "now." : "soon.")])
  }

  function notifyLink(device, connected) {
    Util.execArgv(["notify-send", "-a", "Solaarchy", "-i", notifyIcon(device.kind),
      device.name + (connected ? " connected" : " disconnected"),
      connected ? "Back online." : "No link for 5 minutes: switched off, out of range or asleep."])
  }

  function saveState() {
    var text = JSON.stringify({
      version: 1,
      receivers: receivers,
      devices: devices,
      lowNotified: lowNotified,
      announcedGone: announcedGone
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
    if (Util.isPlainObject(doc.announcedGone))
      announcedGone = Object.assign({}, doc.announcedGone, announcedGone)
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
    checkConnections(null)
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

  // `solaar config` matches a serial, a receiver slot 1..6, or a device
  // name. A receiver pairing's serial is our id. A direct Bluetooth or USB
  // node reports the same unit id, but its Solaar serial is empty, so the
  // serial only hits the asleep receiver slot and the CLI reports that no
  // online device matched. The codename (our name) matches the direct node.
  function solaarDeviceArg(device) {
    if (!device.receiver && device.name) return String(device.name)
    return String(device.id)
  }

  function toggleBacklight(device) {
    device = device || keyboard
    if (!device || !device.backlight || backlightProc.running) return
    setBacklight(device, backlightOn(device) ? 0 : 1)
  }

  // done, if given, is called with true or false once the switch ends.
  function setBacklight(device, target, done) {
    backlightDone = done || null
    var next = Object.assign({}, pendingBacklight)
    next[device.id] = target
    pendingBacklight = next
    actionError = ""
    // Solaar lists a keyboard's backlight choices sorted by value, and their
    // names are translated and differ per model ("Enabled", "Automatic",
    // "Manual"). Disabled is always the highest value and the lowest is always
    // an "on" mode, so pick by position instead of by name. "lowest" rather
    // than "1": Solaar indexes the choices by value, not position, so "1"
    // finds no choice and `solaar config` crashes (seen with Solaar 1.1.20).
    // sh -c exec: a missing binary is sh exiting 127, never a failed start
    // inside the shell process.
    backlightProc.command = ["/bin/sh", "-c", 'exec "$0" "$@"', "solaar", "config",
      solaarDeviceArg(device), "backlight", target === 1 ? "lowest" : "highest"]
    backlightProc.running = true
  }

  // Counting starts when the notices are switched on: a device asleep for
  // hours is not announced right away.
  onNotifyConnectionChanged: {
    offlineSince = ({})
    wasLive = ({})
  }

  // ---- Capabilities and add-ons ----

  // A device's HID++ feature names (Solaar's), from whichever of its links
  // was read: the mouse may have been read over the receiver and be live
  // over Bluetooth now. null until one link has been read.
  function featuresOf(device) {
    for (var i = 0; i < devices.length; i++)
      if (String(devices[i].id) === String(device.id) && devices[i].features) return devices[i].features
    return null
  }

  // What the drawer groups a device's features into. A category gets its own
  // section when something fills it (built in, an add-on, or a known add-on
  // to come); the rest are named on one line, as room for add-ons.
  readonly property var categories: [
    { "id": "lighting", "label": "Lighting", "features": ["BACKLIGHT", "BACKLIGHT2", "BACKLIGHT3",
      "COLOR_LED_EFFECTS", "RGB_EFFECTS", "LED_CONTROL", "PER_KEY_LIGHTING", "PER_KEY_LIGHTING_V2",
      "BRIGHTNESS_CONTROL"] },
    { "id": "haptics", "label": "Haptics", "features": ["HAPTIC", "FORCE_SENSING_BUTTON"] },
    { "id": "buttons", "label": "Buttons", "features": ["REPROG_CONTROLS_V4", "PERSISTENT_REMAPPABLE_ACTION",
      "GESTURE_2", "ONBOARD_PROFILES", "GKEY", "MKEYS", "MR"] },
    { "id": "pointer", "label": "Pointer & scroll", "features": ["ADJUSTABLE_DPI", "EXTENDED_ADJUSTABLE_DPI",
      "SMART_SHIFT", "SMART_SHIFT_ENHANCED", "HIRES_WHEEL", "LOWRES_WHEEL", "THUMB_WHEEL",
      "VERTICAL_SCROLLING", "POINTER_SPEED", "REPORT_RATE", "EXTENDED_ADJUSTABLE_REPORT_RATE"] },
    { "id": "keyboard", "label": "Keyboard", "features": ["FN_INVERSION", "NEW_FN_INVERSION",
      "K375S_FN_INVERSION", "KEYBOARD_DISABLE_KEYS", "KEYBOARD_DISABLE_BY_USAGE", "MULTIPLATFORM",
      "DUALPLATFORM", "LOCK_KEY_STATE", "KEYBOARD_LAYOUT", "KEYBOARD_LAYOUT_2"] },
    { "id": "easyswitch", "label": "Easy-\u2060Switch", "features": ["CHANGE_HOST", "HOSTS_INFO"] }
  ]

  function categoryLabel(id) {
    for (var i = 0; i < categories.length; i++)
      if (categories[i].id === id) return categories[i].label
    return id
  }

  // Built in: the folders under addons/, each with a solaarchy-addon.json
  // like any add-on's, plus its on/off key in Solaarchy's own settings (see
  // addons/ADDONS.md). Read once at start, listed in this order.
  readonly property var builtinIds: ["circadian", "rainbow"]
  property var builtins: []
  // Built-in add-on id -> its service: the part that runs for as long as the
  // widget does.
  property var services: ({})

  function addBuiltin(id, text) {
    if (builtinById(id)) return
    var spec = null
    try { spec = JSON.parse(text) } catch (e) {}
    if (!Util.isPlainObject(spec) || typeof spec.setting !== "string") {
      console.warn("Solaarchy: addons/" + id + "/solaarchy-addon.json is not usable")
      return
    }
    var dir = localPath("addons/" + id)
    var addon = {
      "id": id,
      "builtin": true,
      "dir": dir,
      "category": spec.category,
      "features": Array.isArray(spec.features) ? spec.features : [],
      "label": spec.label || id,
      "icon": spec.icon || "",
      "description": spec.description || "",
      "experimental": spec.experimental === true,
      "setting": spec.setting,
      "drawer": spec.drawer ? dir + "/" + spec.drawer : "",
      "page": spec.page ? dir + "/" + spec.page : "",
      "panel": false
    }
    if (spec.service) {
      var component = Qt.createComponent(Util.fileUrl(dir + "/" + spec.service))
      var service = component.status === Component.Ready
        ? component.createObject(root, { "host": root, "addon": addon }) : null
      if (service) {
        var next = Object.assign({}, services)
        next[id] = service
        services = next
      } else {
        console.warn("Solaarchy: " + id + ": " + component.errorString())
      }
    }
    builtins = builtins.concat([addon]).sort(function(a, b) {
      return builtinIds.indexOf(a.id) - builtinIds.indexOf(b.id)
    })
  }

  function builtinById(id) {
    for (var i = 0; i < builtins.length; i++)
      if (builtins[i].id === id) return builtins[i]
    return null
  }

  // A built-in by its own setting, an installed add-on by Omarchy's plugin switch.
  function addonOn(addon) { return addon.builtin ? boolSetting(addon.setting, false) : !!addon.enabled }

  // Through the service when it has one: Circadian applies at once.
  function setBuiltinOn(addon, on) {
    var service = services[addon.id]
    if (service && typeof service.setOn === "function") service.setOn(on)
    else saveSetting(addon.setting, on)
  }

  // What built-in add-ons add to a keyboard's bulb tooltip, a line each.
  function addonTooltip(device) {
    var lines = []
    for (var i = 0; i < builtins.length; i++) {
      var service = services[builtins[i].id]
      var line = service && typeof service.tooltipFor === "function" ? service.tooltipFor(device) : ""
      if (line) lines.push(line)
    }
    return lines.join("\n")
  }

  // Curated: add-ons reviewed for Solaarchy, listed (and shown greyed where
  // they fit) before they're installed. id: its plugin id, "" until it
  // exists; repo, page: its repository and plugins.omarchy.org page, if any.
  readonly property var curatedAddons: [
    { "id": "", "category": "haptics", "label": "Haptics", "icon": "󰕦", "repo": "", "page": "",
      "note": "Haptic feedback for the MX Master 4, as its own plugin. In development; nothing to install yet." }
  ]

  // solaarchy-addons.py's last answer; re-read each time the panel opens.
  property var addons: []
  property var addonErrors: []

  function installedAddon(id) {
    for (var i = 0; i < addons.length; i++)
      if (id !== "" && addons[i].id === id) return addons[i]
    return null
  }

  // Installed add-ons that aren't curated.
  readonly property var otherAddons: addons.filter(function(a) {
    return !curatedAddons.some(function(c) { return c.id === a.id })
  })

  // An installed add-on's plugin on or off in Omarchy, as `omarchy plugin
  // enable/disable` does; the switch moves at once and the list is read again.
  function setAddonEnabled(addon, on) {
    if (addonToggleProc.running) return
    addons = addons.map(function(a) { return a.id === addon.id ? Object.assign({}, a, { "enabled": on }) : a })
    addonToggleProc.command = ["omarchy", "plugin", on ? "enable" : "disable", addon.id]
    addonToggleProc.running = true
  }

  function openLink(url) {
    Util.execArgv(["uwsm-app", "--", "xdg-open", url])
    close()
  }

  function applyAddons(raw) {
    try {
      var doc = JSON.parse(String(raw).trim())
      addons = Array.isArray(doc.addons) ? doc.addons : []
      addonErrors = Array.isArray(doc.errors) ? doc.errors.map(String) : []
    } catch (e) {
      addonErrors = ["could not list add-ons"]
    }
  }

  // An add-on fits a device with at least one of its features, or of its
  // category's when it names none. A built-in's service can decide instead:
  // Circadian fits exactly the keyboards it switches.
  function addonFits(addon, device, category) {
    if (addon.category !== category) return false
    var service = services[addon.id]
    if (service && typeof service.fits === "function") return service.fits(device)
    var have = featuresOf(device) || []
    var wanted = addon.features && addon.features.length > 0 ? addon.features
      : categories.filter(function(c) { return c.id === category })[0].features
    return wanted.some(function(f) { return have.indexOf(f) >= 0 })
  }

  // The drawer's sections for one device, in category order:
  // {id, label, addons, off, known}, built-ins first. Plus "also": the labels
  // of categories the device has but nothing fills yet.
  function drawerSections(device) {
    var have = featuresOf(device) || []
    var all = builtins.concat(addons)
    var sections = []
    var also = []
    for (var c = 0; c < categories.length; c++) {
      var cat = categories[c]
      var present = cat.features.some(function(f) { return have.indexOf(f) >= 0 })
      // An experimental built-in stays out of sight while it is off.
      var fit = all.filter(function(a) { return addonFits(a, device, cat.id) && (!a.experimental || addonOn(a)) })
      var known = fit.length > 0 || !present ? [] : curatedAddons.filter(function(k) {
        return k.category === cat.id && !installedAddon(k.id)
      })
      if (fit.length > 0 || known.length > 0)
        sections.push({ "id": cat.id, "label": cat.label, "addons": fit.filter(addonOn),
                        "off": fit.filter(function(a) { return !addonOn(a) }), "known": known })
      else if (present)
        also.push(cat.label)
    }
    return { "sections": sections, "also": also }
  }

  // What an add-on's drawer and panel are told about a device.
  function addonDevice(device) {
    return {
      "id": String(device.id),
      "name": device.name,
      "kind": device.kind,
      "online": !!device.online,
      // What `solaar config` and `solaar show` accept for it.
      "selector": solaarDeviceArg(device),
      "features": featuresOf(device) || []
    }
  }

  // ponytail: the public IPC route. The shell API's in-process summon only
  // reaches Solaarchy's own id; if Omarchy closes this, add-ons lose only
  // the button, not their drawer.
  function openAddonPanel(addon, device, extra) {
    var payload = Object.assign({}, extra || {}, { "device": addonDevice(device) })
    Util.execArgv(["omarchy-shell", "shell", "summon", addon.id, JSON.stringify(payload)])
  }

  function scanAddons() {
    if (!addonsProc.running) addonsProc.running = true
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
    var parts = [shown.length === 1 ? "1 device" : shown.length + " devices"]
    var age = ageText()
    if (refreshing) parts.push("reading…")
    else if (age !== "") parts.push(age)
    return parts.join(" · ")
  }

  readonly property string barTooltip: {
    if (!loaded) return lastError !== "" ? "Solaarchy: " + lastError : "Solaarchy: reading devices…"
    var parts = []
    for (var i = 0; i < shown.length; i++) {
      var d = shown[i]
      parts.push(d.name + " " + percentText(d) + (d.battery && d.battery.charging ? " ⚡" : ""))
    }
    if (keyboard) parts.push("Backlight " + (backlightOn(keyboard) ? "on" : "off") + " (right-click)")
    return parts.length > 0 ? parts.join("\n") : "No Logitech devices found"
  }

  onOpenedChanged: {
    if (!opened) return
    actionError = ""
    scanAddons()
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
      var done = root.backlightDone
      root.backlightDone = null
      if (done) done(exitCode === 0)
      root.refresh()
    }
  }

  // One blocking read per built-in, so they are all there before the panel
  // first opens.
  Instantiator {
    model: root.builtinIds
    delegate: FileView {
      required property string modelData
      path: root.localPath("addons/" + modelData + "/solaarchy-addon.json")
      blockLoading: true
      printErrors: false
      onLoaded: root.addBuiltin(modelData, text())
    }
  }

  Process {
    id: addonsProc
    command: ["/usr/bin/python3", root.addonsPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAddons(text)
    }
  }

  Process {
    id: addonToggleProc
    onExited: root.scanAddons()
  }

  // Steppers write once the clicks stop; a write that never comes back
  // (shell busy, `omarchy` missing) stops showing after a few seconds.
  Timer {
    id: settingWriter
    interval: 600
    onTriggered: {
      for (var name in root.pendingSettings) root.writeSetting(name)
    }
  }

  Timer {
    id: pendingExpiry
    interval: 5000
    onTriggered: root.pendingSettings = ({})
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
    onTriggered: {
      root.nowTick++
      if (root.notifyConnection) root.checkConnections(null)
    }
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
