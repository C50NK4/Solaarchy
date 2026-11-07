import QtQuick
import Quickshell.Io

// Circadian, a built-in add-on: every backlit keyboard's light on at civil
// dusk and off at civil dawn, worked out offline by twilight.py. Each keyboard
// is switched once per dusk and once per dawn, so a switch by hand in between
// stands until the next one. Runs for as long as the widget does; with the
// add-on off it only works out the times while Settings or its page shows.
Item {
  id: service
  visible: false

  // Set at creation by BarWidget.qml: the widget, and this add-on's entry.
  property var host
  property var addon

  readonly property bool on: host.addonOn(addon)
  readonly property int offset: host.intSetting("circadianOffset", 0, -120, 120)
  readonly property string location: String(host.cfg("circadianLocation", "")).trim()

  // twilight.py's last answer (see its docstring), or null.
  property var twilight: null
  property string error: ""
  // applied: keyboard id -> {dark, until} of the span (dusk to dawn, or
  // dawn to dusk) it was last switched or found right for, saved so a
  // restart doesn't redo it. Per span, not just on/off: a dawn it never saw
  // live (asleep, on another Easy-Switch host) must not make it skip the
  // next dusk. failed: ids whose switch failed, left until the next twilight
  // check; switching: a write is out.
  property var applied: ({})
  property var failed: ({})
  property bool switching: false
  property bool queued: false

  readonly property bool previewing: host.panelPage === "settings" || host.panelPage === "addon:" + addon.id
  readonly property bool active: on || previewing

  // `shown` has one row per unit, so each keyboard is here once.
  readonly property var backlit: host.shown.filter(function(d) { return !!d.backlight })
  readonly property var keyboards: backlit.filter(follows)

  function skipped(device) { return host.deviceSetting(device, "circadian") === false }
  function follows(device) { return on && !!device.backlight && !skipped(device) }
  // Where its drawer row shows: the same keyboards it can switch.
  function fits(device) { return !!device.backlight }

  // ---- Switching ----

  // The span now. Consecutive spans of one kind end about a day apart, so
  // 12 h of slack absorbs a recomputed or slightly shifted end, never a new span.
  function span() { return { "dark": twilight.dark, "until": twilight.until || 0 } }
  function done(id) {
    var a = applied[id]
    return !!a && typeof a === "object" && a.dark === twilight.dark
      && Math.abs((a.until || 0) - (twilight.until || 0)) < 43200
  }

  function forget(list) {
    var next = Object.assign({}, applied)
    for (var i = 0; i < list.length; i++) delete next[String(list[i].id)]
    applied = next
  }

  // Switched on, it applies at once rather than at the next dusk or dawn.
  function setOn(value) {
    if (value && !on) forget(backlit.filter(function(d) { return !skipped(d) }))
    host.saveSetting(addon.setting, value)
  }

  // follow false skips this keyboard; true follows again, at once.
  function setFollow(device, follow) {
    if (follow && on && skipped(device)) forget([device])
    host.saveDeviceSetting(device, "circadian", follow ? undefined : false)
  }

  // One keyboard at a time: the read after each switch comes back here.
  function apply() {
    if (!twilight || switching || host.backlightBusy) return
    var settled = false
    for (var i = 0; i < backlit.length; i++) {
      var d = backlit[i]
      var id = String(d.id)
      if (!follows(d) || done(id) || failed[id]) continue
      if (!host.isLive(d)) continue  // tried again after the next read
      if (host.backlightOn(d) === twilight.dark) {
        applied[id] = span()
        settled = true
        continue
      }
      switchKeyboard(d, twilight.dark)
      break
    }
    if (settled) save()
  }

  // A failed switch waits for the next twilight check, not the next read,
  // which would loop on a keyboard that keeps refusing.
  function switchKeyboard(device, on) {
    var id = String(device.id)
    var now = span()  // the span this switch is for, even if it ends mid-write
    switching = true
    host.setBacklight(device, on ? 1 : 0, function(ok) {
      switching = false
      if (ok) applied[id] = now
      else failed[id] = true
      save()
    })
  }

  Connections {
    target: service.host
    function onStatusApplied() { service.apply() }
    function onDeviceSettingsChanged() { service.apply() }
    // Timers stop counting while the computer sleeps; the widget's 30 s tick
    // switches soon after waking past a dusk or dawn.
    function onNowTickChanged() {
      if (service.active && service.answer && (service.answerDay !== service.today()
          || (service.twilight.until && Date.now() >= service.twilight.until * 1000)))
        service.wake()
    }
  }

  onOnChanged: apply()

  // ---- Dusk and dawn ----

  // twilight.py runs once a day, just after local midnight, and again only
  // when the offset or location changes. Its answer lists the switches
  // ahead, so a dusk or dawn moves `twilight` on without running it.
  property var answer: null     // twilight.py's last answer, or null
  property string answerDay: "" // the local date it was worked out on
  property string answerFor: "" // the offset and location it was asked with

  function today() { return new Date().toDateString() }
  function fresh() { return !!answer && answerDay === today() && answerFor === offset + "|" + location }

  // The command is built here, not bound: a settings change handler runs
  // before the binding would have caught up, and the helper got the old value.
  function runTwilight() {
    if (!active) return
    if (twilightProc.running) { queued = true; return }
    answerFor = offset + "|" + location
    twilightProc.command = ["/usr/bin/python3", addon.dir + "/twilight.py", String(offset), location]
    twilightProc.running = true
  }

  function applyTwilight(raw) {
    var doc = null
    try { doc = JSON.parse(String(raw).trim()) } catch (e) { doc = { error: "could not work out dusk and dawn" } }
    error = doc.error ? String(doc.error) : ""
    answer = doc.error ? null : doc
    answerDay = answer ? today() : ""
    failed = ({})
    advance()
  }

  // Dark or not at `at`, and until when, from [unix time, dark after] switches.
  function stateAt(list, darkThen, at) {
    var dark = darkThen
    for (var i = 0; i < (list || []).length; i++) {
      if (list[i][0] > at) return { "dark": dark, "until": list[i][0] }
      dark = list[i][1]
    }
    return { "dark": dark, "until": null }
  }

  function advance() {
    var now = Date.now()
    if (answer) {
      var s = stateAt(answer.changes, answer.dark, now / 1000)
      var o = stateAt(answer.outsideChanges, answer.outsideDark, now / 1000)
      twilight = Object.assign({}, answer, { "dark": s.dark, "until": s.until,
                                             "outsideDark": o.dark, "outsideUntil": o.until })
    } else twilight = null
    // Wake at the next switch or just after midnight; after a failure, in an hour: a failure is
    // almost always a setting (a bad location), which a retry won't fix.
    var midnight = new Date(now)
    midnight.setHours(24, 0, 5, 0)
    var next = !answer ? now + 3600000
      : Math.min(midnight.getTime(), twilight.until ? twilight.until * 1000 + 2000 : Infinity)
    twilightTimer.interval = Math.max(5000, next - now)
    if (active) twilightTimer.restart()
    apply()
  }

  function wake() { fresh() ? advance() : runTwilight() }

  onActiveChanged: active ? wake() : twilightTimer.stop()
  onOffsetChanged: runTwilight()
  onLocationChanged: runTwilight()
  Component.onCompleted: runTwilight()

  Process {
    id: twilightProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.applyTwilight(text)
    }
    onExited: {
      if (!service.queued) return
      service.queued = false
      Qt.callLater(service.runTwilight)
    }
  }

  Timer {
    id: twilightTimer
    onTriggered: service.wake()
  }

  // ---- Saved state ----

  function save() { stateFile.setText(JSON.stringify({ "applied": applied }) + "\n") }

  FileView {
    id: stateFile
    path: service.host.home + "/.local/state/omarchy/solaarchy-circadian.json"
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var doc = JSON.parse(text())
        if (doc && typeof doc.applied === "object") service.applied = Object.assign({}, doc.applied, service.applied)
      } catch (e) {}
    }
  }

  // ---- Words ----

  // Minutes since midnight, and a Unix time, as local "HH:MM".
  function clockText(minute) {
    var h = Math.floor(minute / 60) % 24
    var m = Math.round(minute % 60)
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
  }

  function timeText(seconds) {
    var d = new Date(seconds * 1000)
    return clockText(d.getHours() * 60 + d.getMinutes())
  }

  readonly property string timesText: !twilight ? ""
    : twilight.dusk && twilight.dawn ? "on at " + twilight.dusk + ", off at " + twilight.dawn
    : twilight.dark ? "on all day today" : "off all day today"

  // Settings: the add-on's row.
  readonly property bool captionUrgent: error !== ""
  readonly property string caption: error !== "" ? error
    : backlit.length === 0 ? "Keyboard light on at dusk, off at dawn. No backlit keyboard yet."
    : timesText !== "" ? "Keyboard light " + timesText
    : "Keyboard light on at dusk, off at dawn"

  // The devices page: only while it would switch something.
  readonly property string message: error !== "" && keyboards.length > 0 ? "Circadian is paused: " + error : ""

  // The bulb's tooltip.
  function tooltipFor(device) {
    return follows(device) && timesText !== "" ? "Circadian: " + timesText : ""
  }

  // ---- Keyboard cursor ----

  // Actions are "<add-on id>.<verb>[:<device id>]"; Panel.qml hands them to run().
  readonly property var pageActions: ["circadian.toggle", "circadian.offset-minus", "circadian.offset-plus",
                                      "circadian.loc-omarchy", "circadian.loc-custom"]

  // Asked only while it is on, for the keyboard whose drawer is open.
  function drawerActions(device) { return ["circadian.follow:" + device.id, "addon-page:circadian"] }

  // The page listens: Custom puts the keys into the location field.
  signal locationModeRequested(bool custom)

  function run(verb, device) {
    if (verb === "toggle") setOn(!on)
    else if (verb === "follow") { if (device) setFollow(device, skipped(device)) }
    else if (verb === "offset-minus") host.stepSetting("circadianOffset", offset, -5, -120, 120)
    else if (verb === "offset-plus") host.stepSetting("circadianOffset", offset, 5, -120, 120)
    else if (verb === "loc-omarchy" || verb === "loc-custom") locationModeRequested(verb === "loc-custom")
  }
}
