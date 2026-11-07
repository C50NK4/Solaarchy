import QtQuick
import Quickshell.Io

// LED, a built-in add-on: the LED control of every paired Logitech mouse —
// the master switch, one cycler that moves all zones to the same next effect
// so they stay in lock-step, and a hue slider for the effects that carry a
// color. Every write goes through `solaar config`, one at a time; every read
// comes from led-state.py, which takes the same lock as the core's status
// read. The drawer is rebuilt at any time, so all the state lives here,
// keyed by device id: the last read per device and what is in flight.
Item {
  id: service
  visible: false

  // Set at creation by BarWidget.qml: the widget, and this add-on's entry.
  property var host
  property var addon

  readonly property bool on: host.addonOn(addon)

  // Device id (string) -> the last read's "led" object, or null. Kept on
  // purpose: a zone that could not be read this time keeps the last good
  // answer instead of the cycler falling back to defaults.
  property var ledByDevice: ({})
  // Device id -> 0/1 while the master switch is in flight (optimistic UI).
  property var pendingControl: ({})
  // "id:zone location" -> effectId while a zone effect cycle is in flight.
  property var pendingEffect: ({})
  // "id:zone location" -> color while a zone color write is in flight.
  property var pendingColor: ({})
  // Shown in the devices page's message row, like circadian's error. Clears
  // on the next core read, like the core's own error.
  property string message: ""
  // led-state.py reads Solaar's saved settings, and a zone's effect is often
  // only saved once it has been set.
  readonly property string noStateHint: "Set an effect in Solaar once to control it here"

  readonly property bool busy: writeProc.running
  readonly property bool reading: readProc.running

  // ---- What a device's LED is doing ----

  // One of the add-on's features is on the device's feature list, read
  // awake. The drawer row only appears for these devices anyway.
  function hasLedFeature(device) {
    var feats = host.featuresOf(device)
    if (!feats || typeof feats.indexOf !== "function") return false
    return feats.indexOf("COLOR_LED_EFFECTS") >= 0 || feats.indexOf("RGB_EFFECTS") >= 0
  }

  function ledFor(id) { return service.ledByDevice[id] || null }

  // `solaar config` matches a serial, a receiver slot 1..6, or a device
  // name. The drawer's snapshot carries the arg it was matched by; a live
  // device from the core falls back to the core's own rule.
  function solaarArg(device) {
    if (device.selector) return String(device.selector)
    return host.solaarDeviceArg(device)
  }

  // An array that crossed a QJSValue boundary (the read JSON, a property of
  // a device) comes back wrapped: Array.isArray() rejects it although
  // .length and index access still work, so test the shape, not the
  // constructor.
  function isList(value) {
    return value !== null && typeof value === "object" && typeof value.length === "number"
  }

  // The zone object of the read at the location (1-based, Solaar's).
  function ledZone(led, location) {
    if (!led || !service.isList(led.zones)) return null
    for (var i = 0; i < led.zones.length; i++)
      if (led.zones[i].location === location) return led.zones[i]
    return null
  }

  // The effect entry in a zone's list that the effectId names, or null.
  function ledEffectEntry(led, location, effectId) {
    var zone = service.ledZone(led, location)
    if (!zone || !service.isList(zone.effects)) return null
    for (var i = 0; i < zone.effects.length; i++)
      if (zone.effects[i].id === effectId) return zone.effects[i]
    return null
  }

  // There is a saved effect to cycle from.
  function hasZones(id) {
    var led = service.ledFor(id)
    return !!led && service.isList(led.zones) && led.zones.length > 0
  }

  function controlOn(id) {
    var pending = service.pendingControl[id]
    if (pending !== undefined) return pending === 1
    var led = service.ledFor(id)
    return !!led && !!led.control
  }

  // A write for this device is in flight: the master switch, or any zone.
  function busyFor(id) {
    if (!service.busy) return false
    if (service.pendingControl[id] !== undefined) return true
    // pendingEffect and pendingColor keys are "id:location", so a plain
    // index never hits.
    var prefix = id + ":"
    for (var key in service.pendingEffect)
      if (String(key).indexOf(prefix) === 0) return true
    for (var k in service.pendingColor)
      if (String(k).indexOf(prefix) === 0) return true
    return false
  }

  // The id of the effect a zone is on, pending-aware: while a cycler write
  // is in flight the cache the read script sees still reports the old
  // effect, so any decision about what comes next must run off the
  // optimistic id, not the confirmed one. Running off the confirmed id was
  // the stuck-at-Breathe bug — a click inside the confirm window re-derived
  // from the stale effect and re-requested the one just shown.
  function zoneEffectId(id, led, location) {
    var pending = service.pendingEffect[id + ":" + location]
    if (pending !== undefined) return pending
    var zone = service.ledZone(led, location)
    return zone ? zone.effectId : -1
  }

  // The effect a zone is on, or the one a cycler just requested while its
  // write is in flight (optimistic), so the label flips with the click.
  function zoneEffect(id, led, location) {
    var pending = service.pendingEffect[id + ":" + location]
    if (pending !== undefined) {
      var entry = service.ledEffectEntry(led, location, pending)
      if (entry && entry.name) return entry.name
    }
    var zone = service.ledZone(led, location)
    return zone ? zone.effect : null
  }

  // The effect the linked cycler points at: the first zone's, since all
  // zones move to the same effect on every click and the first one is the
  // reference. A pair that somehow drifted apart re-syncs on the next click.
  function linkedEffect(id) {
    var led = service.ledFor(id)
    if (!led || !service.isList(led.zones) || led.zones.length === 0)
      return null
    return service.zoneEffect(id, led, led.zones[0].location)
  }

  // The effect entry the linked cycler points at (first zone, pending-
  // aware), or null when the device has no LED zone. The drawer uses it to
  // decide whether the linked effect carries a color param at all.
  function linkedEntry(id) {
    var led = service.ledFor(id)
    if (!led || !service.isList(led.zones) || led.zones.length === 0)
      return null
    var ref = led.zones[0]
    return service.ledEffectEntry(led, ref.location, service.zoneEffectId(id, led, ref.location))
  }

  // A zone's color, pending-aware: while a color write is in flight the
  // cache the read script sees still reports the old color, so the slider
  // runs off the optimistic value, like the cycler runs off its id.
  // -1 when the zone's effect carries no color param (or the read has none).
  function zoneColor(id, led, location) {
    var pending = service.pendingColor[id + ":" + location]
    if (pending !== undefined) return pending
    var zone = service.ledZone(led, location)
    if (!zone || !zone.params || typeof zone.params.color !== "number") return -1
    return zone.params.color
  }

  // The hue (0..360) the color slider rests at while idle: the reference
  // zone's color, or -1 when the linked effect carries no color param
  // (Cycle, Disabled, ...), which is when the slider stays hidden — the
  // effect entry must both exist and accept "color", a Cycle entry has no
  // color to rest on even though it is a real entry. A gray color (white,
  // black) has no hue of its own and rests at red, the track's left edge.
  function zoneHue(id) {
    var led = service.ledFor(id)
    if (!led) return -1
    var entry = service.linkedEntry(id)
    if (!entry || (entry.params || []).indexOf("color") < 0) return -1
    var color = service.zoneColor(id, led, led.zones[0].location)
    if (color < 0) return 0
    var hue = service.rgbToHue(color)
    return hue < 0 ? 0 : hue
  }

  // 0..360 hue -> 0xRRGGBB int at full saturation and brightness: Solaar's
  // color param is an RGB int, and a hue-only slider means "a color", not a
  // tint of one, so both stay 1.
  function hueToRgb(h) {
    h = ((h % 360) + 360) % 360
    var x = 1 - Math.abs((h / 60) % 2 - 1)
    var r = 0, g = 0, b = 0
    if (h < 60) { r = 1; g = x }
    else if (h < 120) { r = x; g = 1 }
    else if (h < 180) { g = 1; b = x }
    else if (h < 240) { g = x; b = 1 }
    else if (h < 300) { r = x; b = 1 }
    else { r = 1; b = x }
    return Math.round(r * 255) * 65536 + Math.round(g * 255) * 256 + Math.round(b * 255)
  }

  // hueToRgb as a "#RRGGBB" string for QML's color properties: they do not
  // accept a raw int — the binding fails silently and the knob stays black.
  function hueToColor(h) {
    var rgb = service.hueToRgb(h)
    function hex(n) { return (n < 16 ? "0" : "") + n.toString(16) }
    return "#" + hex(rgb >> 16) + hex((rgb >> 8) & 0xff) + hex(rgb & 0xff)
  }

  // 0xRRGGBB int -> hue 0..360; -1 for a gray (white, black) that carries
  // no hue.
  function rgbToHue(rgb) {
    var r = Math.floor(rgb / 65536) / 255
    var g = Math.floor((rgb % 65536) / 256) / 255
    var b = (rgb % 256) / 255
    var max = Math.max(r, g, b)
    var min = Math.min(r, g, b)
    var d = max - min
    if (d === 0) return -1
    var h
    if (max === r) h = 60 * (((g - b) / d + 6) % 6)
    else if (max === g) h = 60 * ((b - r) / d + 2)
    else h = 60 * ((r - g) / d + 4)
    return (h + 360) % 360
  }

  // The bulb on the device's row, in the same name-trailing free space as
  // the keyboard backlight bulb: the LED control master switch. null for a
  // device without the LED feature, or while the add-on is switched off in
  // Settings (its drawer then says so instead). Like the drawer, it only
  // ever reads; the row is rebuilt whenever the device changes.
  function rowBulb(device) {
    if (!device || !service.on) return null
    if (!service.hasLedFeature(device)) return null
    var id = String(device.id)
    var on = service.controlOn(id)
    var busy = service.busyFor(id)
    return {
      "on": on,
      "busy": busy,
      "enabled": !!device.online && !!service.ledFor(id) && !busy,
      "tooltip": busy ? "Switching LED control…"
        : !service.ledFor(id) ? service.noStateHint
        // Off hands the LEDs back to the firmware, which may keep them lit.
        : on ? "LED control on: click to give the LEDs back to the mouse"
        : "LED control off, the mouse's own lighting: click to turn on",
      "action": "led.control:" + id
    }
  }

  // ---- The drawer's actions, routed by Panel.qml through run() ----

  // The control switch is the row bulb, so the drawer's cursor walks the
  // cycler alone.
  function drawerActions(device) {
    return ["led.effect:" + device.id]
  }

  function run(verb, device) {
    if (verb === "control") service.toggleControl(device)
    else if (verb === "effect") service.cycleEffect(device)
  }

  // ---- Reads ----

  // led-state.py for the devices that list an LED feature, one read. It
  // takes the core's lock and pings each device, so it only runs when there
  // is something to read.
  function read() {
    if (!service.on || service.reading) return
    var ids = []
    for (var i = 0; i < host.devices.length; i++) {
      var d = host.devices[i]
      if (service.hasLedFeature(d) && ids.indexOf(String(d.id)) < 0)
        ids.push(String(d.id))
    }
    if (ids.length === 0) return
    readProc.command = ["/usr/bin/python3", addon.dir + "/led-state.py", "--ids=" + ids.join(",")]
    readProc.running = true
  }

  function applyLedRead(raw) {
    var doc = null
    try { doc = JSON.parse(String(raw).trim()) } catch (e) { doc = null }
    if (!doc || !service.isList(doc.devices)) return
    var next = Object.assign({}, service.ledByDevice)
    for (var i = 0; i < doc.devices.length; i++) {
      var d = doc.devices[i]
      if (!d || d.led === undefined) continue
      // null (offline, or not asked for this time) keeps the last good
      // answer.
      if (d.led) next[String(d.id)] = d.led
      service.confirmLed(String(d.id), d.led)
    }
    service.ledByDevice = next
  }

  // A read can only confirm pending LED state, never settle it: the cache
  // the read script sees lags a successful write by ~5 s (with the Solaar
  // GUI running, `solaar config` writes the device and the GUI persists it
  // on its own deferred-save timer), so a read that arrives before the lag
  // has elapsed reports the old effect and must not clear the optimistic
  // label. Confirmation is per device: drop the pending control when the
  // read reports the value we asked for, each pending zone when its effect
  // does, and each pending color when its zone's color param does.
  function confirmLed(id, led) {
    if (!led) return
    var pending = service.pendingControl[id]
    if (pending !== undefined && led.control === (pending === 1)) {
      var next = Object.assign({}, service.pendingControl)
      delete next[id]
      service.pendingControl = next
    }
    // pendingEffect and pendingColor keys are "id:location"; recover the
    // location.
    var prefix = id + ":"
    for (var key in service.pendingEffect) {
      if (String(key).indexOf(prefix) !== 0) continue
      var zone = service.ledZone(led, parseInt(key.slice(prefix.length), 10))
      if (zone && zone.effectId === service.pendingEffect[key]) {
        var rest = Object.assign({}, service.pendingEffect)
        delete rest[key]
        service.pendingEffect = rest
      }
    }
    // A color write keeps the zone's effect and changes only its color
    // param, so it confirms on the read reporting that color on that zone.
    for (var key in service.pendingColor) {
      if (String(key).indexOf(prefix) !== 0) continue
      var zone = service.ledZone(led, parseInt(key.slice(prefix.length), 10))
      if (zone && zone.params && zone.params.color === service.pendingColor[key]) {
        var rest = Object.assign({}, service.pendingColor)
        delete rest[key]
        service.pendingColor = rest
      }
    }
  }

  // Force-settle every pending LED state, no read involved: the belt for a
  // write that never confirms. Not guarded on busy: inside writeProc's
  // onExited the binding still says running, so a guard here would skip the
  // settle of a failed write. The settle timer checks for a newer write itself.
  function settleLed() {
    service.pendingControl = ({})
    service.pendingEffect = ({})
    service.pendingColor = ({})
  }

  // ---- Writes, one at a time, through `solaar config` ----

  function toggleControl(device) {
    if (!device) return
    var id = String(device.id)
    var led = service.ledFor(id)
    if (!led || service.busy) return
    var target = service.controlOn(id) ? 0 : 1
    var next = Object.assign({}, service.pendingControl)
    next[id] = target
    service.pendingControl = next
    service.message = ""
    // controlSetting comes from the read JSON; it is "rgb_control" on the
    // newer RGB_EFFECTS mice (G502/G700/G900 family), "led_control" on the
    // G403-style COLOR_LED_EFFECTS ones.
    writeProc.command = service.locked(["/bin/sh", "-c", 'exec "$0" "$@"', "solaar", "config",
      service.solaarArg(device), led.controlSetting || "led_control",
      target === 1 ? "true" : "false"])
    writeProc.running = true
  }

  // Cycle every LED zone of the device to the next effect in the list the
  // firmware advertises — one button drives all zones, and each zone moves
  // to the same next effect, so a pair that drifted apart re-syncs on the
  // first click. Each zone is sent the effect's id with its defaults, then
  // the params the zone's current effect already sets where the new one has
  // them, so cycling back keeps a user's tuning (a custom Cycle period
  // survives a trip to Static and home). A color param that no source gives
  // a value for becomes white: Solaar's LEDEffectSetting.to_bytes() would
  // fill it with 0, which is black.
  function cycleEffect(device) {
    if (!device) return
    var id = String(device.id)
    var led = service.ledFor(id)
    if (!led || service.busy) return
    var zones = led.zones
    if (!service.isList(zones) || zones.length === 0) return
    // The first zone is the reference: its effect decides which comes next.
    var ref = zones[0]
    if (!service.isList(ref.effects) || ref.effects.length === 0) return
    var order = []
    // Nameless: an effect Solaar's table doesn't know, which `solaar config`
    // can't write, so it would stop the cycler right there.
    for (var i = 0; i < ref.effects.length; i++)
      if (ref.effects[i].name) order.push(ref.effects[i].id)
    if (order.length === 0) return
    // Pending-aware: the label already shows the in-flight effect, so the
    // next step must start where the user sees the cycler, or the list
    // stops at the last entry instead of wrapping (the Breathe bug).
    var nextId = order[(order.indexOf(service.zoneEffectId(id, led, ref.location)) + 1) % order.length]
    // `solaar config` takes one setting per invocation, so the zones are
    // chained in one shell: one process, one pending state, one confirm
    // cycle. && so an unreachable device skips the remaining writes.
    var arg = service.shellQuote(service.solaarArg(device))
    // The zone setting name differs per feature family: led_zone_N on the
    // G403-style COLOR_LED_EFFECTS mice, rgb_zone_N on the newer RGB_EFFECTS
    // ones; the read script reports which one this device's cache uses.
    // The value tag stays !LEDEffectSetting either way — Solaar persists
    // both families with the same class.
    var zonePrefix = led.zoneSettingPrefix || "led_zone_"
    var cmds = []
    var pending = Object.assign({}, service.pendingEffect)
    for (var z = 0; z < zones.length; z++) {
      var zone = zones[z]
      var entry = service.ledEffectEntry(led, zone.location, nextId)
      var params = {}
      if (entry) {
        for (var p in entry.defaults || {}) params[p] = entry.defaults[p]
        var names = entry.params || []
        for (var k in zone.params || {})
          if (names.indexOf(k) >= 0) params[k] = zone.params[k]
        if (names.indexOf("color") >= 0 && !(params.color > 0)) params.color = 16777215
      }
      var yaml = "ID: " + nextId
      for (var q in params) yaml += ", " + q + ": " + params[q]
      cmds.push("solaar config " + arg + " " + zonePrefix + zone.location +
        " '!LEDEffectSetting {" + yaml + "}'")
      pending[id + ":" + zone.location] = nextId
    }
    // Used while the control is off, the change turns it back on first — the
    // chain starts with the control setting, and the row bulb follows the
    // write home, like Circadian's settings re-enable the keyboard light.
    var pendingCtl = Object.assign({}, service.pendingControl)
    if (!service.controlOn(id)) {
      pendingCtl[id] = 1
      cmds.unshift("solaar config " + arg + " " + (led.controlSetting || "led_control") + " true")
    }
    service.pendingEffect = pending
    service.pendingControl = pendingCtl
    service.message = ""
    // The chain is the shell command itself (the args are quoted above),
    // not positional parameters as in the single-setting calls.
    writeProc.command = service.locked(["/bin/sh", "-c", cmds.join(" && ")])
    writeProc.running = true
  }

  // Move every zone that carries a color param to the given color, keeping
  // each zone's own (pending-aware) effect and its other params: one slider
  // drives the whole device, like the cycler, and each zone is written its
  // current effect id + params with color replaced. The zone keeps its
  // effect, so no pending effect is set — only the color — and a zone whose
  // effect somehow has no color param is skipped.
  function setColor(device, color) {
    if (!device) return
    var id = String(device.id)
    var led = service.ledFor(id)
    if (!led || service.busy) return
    var zones = led.zones
    if (!service.isList(zones) || zones.length === 0) return
    var arg = service.shellQuote(service.solaarArg(device))
    var zonePrefix = led.zoneSettingPrefix || "led_zone_"
    var cmds = []
    var pending = Object.assign({}, service.pendingColor)
    for (var z = 0; z < zones.length; z++) {
      var zone = zones[z]
      var effectId = service.zoneEffectId(id, led, zone.location)
      var entry = service.ledEffectEntry(led, zone.location, effectId)
      if (!entry || (entry.params || []).indexOf("color") < 0) continue
      var params = {}
      for (var p in entry.defaults || {}) params[p] = entry.defaults[p]
      var names = entry.params || []
      for (var k in zone.params || {})
        if (names.indexOf(k) >= 0) params[k] = zone.params[k]
      params.color = color
      var yaml = "ID: " + effectId
      for (var q in params) yaml += ", " + q + ": " + params[q]
      cmds.push("solaar config " + arg + " " + zonePrefix + zone.location +
        " '!LEDEffectSetting {" + yaml + "}'")
      pending[id + ":" + zone.location] = color
    }
    if (cmds.length === 0) return
    // Like the cycler: a change made while the control is off turns it back
    // on first, and the row bulb follows the write home.
    var pendingCtl = Object.assign({}, service.pendingControl)
    if (!service.controlOn(id)) {
      pendingCtl[id] = 1
      cmds.unshift("solaar config " + arg + " " + (led.controlSetting || "led_control") + " true")
    }
    service.pendingColor = pending
    service.pendingControl = pendingCtl
    service.message = ""
    writeProc.command = service.locked(["/bin/sh", "-c", cmds.join(" && ")])
    writeProc.running = true
  }

  // Under the core's lock, like every device access. A read can hold it for
  // about as long as the write's own timeout, so give up waiting well before
  // that: flock then exits 1, and the write fails instead of timing out.
  function locked(command) {
    return ["flock", "-w", "10", host.lockPath].concat(command)
  }

  // Single-quote for the chained `sh -c` command: the device arg is a name
  // with spaces on a directly connected node, and the whole chain is one
  // shell string, so the per-argument quoting of the single-setting calls
  // no longer applies.
  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  // ---- Processes and timers ----

  // led-state.py: the read, through the core's lock.
  Process {
    id: readProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.applyLedRead(text)
    }
  }

  // The master switch, the zone cycler and the color share this one
  // process: a second click is dropped while the first write is still in
  // flight.
  Process {
    id: writeProc
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        // The write failed: nothing will ever confirm the optimistic state,
        // so settle it now and re-read to show the truth.
        confirmTimer.stop()
        settleTimer.stop()
        service.settleLed()
        service.message = exitCode === 127 ? "solaar is not installed" : "Could not change the LED settings"
        service.read()
        return
      }
      // A successful write is not visible in the cache the read script sees
      // for ~5 s, so a read now would only report the old effect. Let the
      // timers below fetch the first read that can confirm the optimistic
      // state, and belt it if no read ever does.
      confirmTimer.restart()
      settleTimer.restart()
    }
  }

  Timer {
    interval: 20000
    running: writeProc.running
    onTriggered: {
      writeProc.running = false
      service.settleLed()
      service.message = "Timed out changing the LED settings"
    }
  }

  // The first read that can confirm the optimistic LED state: the write
  // time plus the ~5 s persistence lag of the running Solaar GUI, plus
  // margin. When it arrives, confirmLed drops the pending entries and the
  // label simply stops being optimistic — no visible change, because the
  // write succeeded.
  Timer {
    id: confirmTimer
    interval: 8000
    repeat: false
    onTriggered: service.read()
  }

  // Belt for a write that never confirms: the device was asleep, the write
  // was lost, or the Solaar GUI never persisted the change. Force-settle
  // the optimistic state and re-read so the panel shows the truth.
  Timer {
    id: settleTimer
    interval: 16000
    repeat: false
    onTriggered: {
      if (service.busy) return  // a newer write owns the pending state now
      var hadPending = Object.keys(service.pendingControl).length > 0
                     || Object.keys(service.pendingEffect).length > 0
                     || Object.keys(service.pendingColor).length > 0
      if (!hadPending) return  // already confirmed by a read: nothing to do
      service.settleLed()
      service.read()
    }
  }

  Component.onCompleted: service.read()

  // The core's read is the moment a device's feature list turns up or a
  // device comes back: re-read the LED state then.
  Connections {
    target: host
    function onStatusApplied() {
      service.message = ""
      service.read()
    }
  }

  onOnChanged: service.read()
}
