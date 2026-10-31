import QtQuick
import qs.Commons
import qs.Ui

// Dark hours: today as a 24-hour strip (filled = backlight on), the offset
// from civil twilight, and where dusk and dawn are worked out for.
Column {
  id: page

  // Set at creation by PanelContent.qml: the bar widget and the panel.
  property var w
  property var view

  // Timezone or Custom. Custom stays picked while its field is still empty.
  property bool customLocation: w.darkHoursLocation !== ""
  readonly property var twilight: w.twilight
  readonly property int offset: w.darkHoursOffset
  // Dark hours on, with a keyboard that follows it.
  readonly property bool active: w.darkKeyboards.length > 0

  width: parent ? parent.width : 0
  spacing: Style.space(14)

  function chooseLocation(custom) {
    customLocation = custom
    if (!custom) {
      if (w.darkHoursLocation !== "") w.saveSetting("darkHoursLocation", "")
      view.restoreFocus()
    } else {
      locationField.forceActiveFocus()
    }
  }

  function saveLocation() {
    var text = locationField.text.trim()
    if (text !== w.darkHoursLocation) w.saveSetting("darkHoursLocation", text)
  }

  Connections {
    target: page.view
    function onLocationModeRequested(custom) { page.chooseLocation(custom) }
  }

  PageHeader {
    view: page.view
    title: "Dark hours"
    backTooltip: page.view.backPage === "settings" ? "Back to settings" : "Back to devices"

    ToggleSwitch {
      anchors.verticalCenter: parent.verticalCenter
      checked: page.w.darkHours
      foreground: page.view.fg
      hasCursor: page.view.hasCursorOn("dark-toggle")
      onToggled: page.w.setDarkHours(!page.w.darkHours)
      onHovered: function(h) { page.view.hoverAction("dark-toggle", h) }
    }
  }

  PanelSeparator { foreground: page.view.fg }

  // ---- Today ----
  Column {
    width: parent.width
    spacing: Style.space(6)
    // A preview while nothing follows it: the same day, dimmed.
    opacity: page.active ? 1.0 : 0.55

    Text {
      visible: !page.twilight
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: page.w.twilightError !== "" ? page.w.twilightError : "Working out dusk and dawn…"
      color: page.w.twilightError !== "" ? page.view.urgent : page.view.dim
      font.family: page.view.fontFamily
      font.pixelSize: Style.font.caption
    }

    Item {
      id: timeline
      visible: !!page.twilight
      width: parent.width
      readonly property var spans: page.twilight && page.twilight.darkToday ? page.twilight.darkToday : []
      readonly property real nowMinute: {
        page.w.nowTick  // re-evaluate on the ticker
        var d = new Date()
        return d.getHours() * 60 + d.getMinutes()
      }
      readonly property real labelHeight: Style.font.caption + Style.space(4)
      implicitHeight: labelHeight + strip.height + Style.space(4) + labelHeight

      function xAt(minute) { return Math.round(strip.width * minute / 1440) }

      // Switch times over the strip: "on" where a dark span starts, "off"
      // where one ends; midnight is not a switch.
      Repeater {
        model: {
          var marks = []
          for (var i = 0; i < timeline.spans.length; i++) {
            var s = timeline.spans[i]
            if (s[0] > 0) marks.push({ "minute": s[0], "on": true })
            if (s[1] < 1440) marks.push({ "minute": s[1], "on": false })
          }
          return marks
        }

        Text {
          required property var modelData
          x: Math.max(0, Math.min(timeline.width - width, timeline.xAt(modelData.minute) - width / 2))
          y: 0
          textFormat: Text.PlainText
          text: (modelData.on ? "on " : "off ") + page.w.clockText(modelData.minute)
          color: page.view.fg
          font.family: page.view.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Rectangle {
        id: strip
        y: timeline.labelHeight
        width: parent.width
        height: Style.space(14)
        radius: Math.min(Style.cornerRadius, height / 2)
        color: Qt.rgba(page.view.fg.r, page.view.fg.g, page.view.fg.b, 0.12)

        Repeater {
          model: timeline.spans

          Rectangle {
            required property var modelData
            x: timeline.xAt(modelData[0])
            width: timeline.xAt(modelData[1]) - x
            height: strip.height
            radius: strip.radius
            color: page.view.fg
          }
        }

        // Now: a notch through the strip in the panel's own background, so
        // it shows on light and dark parts alike.
        Rectangle {
          x: Math.max(0, Math.min(strip.width - width, timeline.xAt(timeline.nowMinute) - width / 2))
          y: -Style.space(3)
          width: Math.max(2, Style.space(3))
          height: strip.height + Style.space(6)
          radius: width / 2
          color: Style.selectedStateColor(page.view.fg, Color.accent)
        }
      }

      Repeater {
        model: [0, 6, 12, 18, 24]

        Text {
          required property var modelData
          x: Math.max(0, Math.min(timeline.width - width, timeline.xAt(modelData * 60) - width / 2))
          y: strip.y + strip.height + Style.space(4)
          textFormat: Text.PlainText
          text: (modelData < 10 ? "0" : "") + modelData
          color: page.view.dim
          font.family: page.view.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Text {
      visible: !!page.twilight
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: !page.twilight ? ""
        : (page.twilight.dark ? "Dark now" : "Light now")
          + (page.twilight.until ? ", until " + page.w.timeText(page.twilight.until) : "")
          + (page.active ? "" : !page.w.darkHours ? ". Dark hours is off." : ". Nothing follows dark hours yet.")
      color: page.view.dim
      font.family: page.view.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // ---- Offset ----
  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "OFFSET"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    OptionRow {
      view: page.view
      glyph: "󰔛"
      label: page.offset === 0 ? "At twilight" : (page.offset > 0 ? "Longer" : "Shorter")
      caption: page.offset === 0 ? "On at dusk, off at dawn"
        : page.offset > 0 ? "On " + page.offset + " min before dusk, off " + page.offset + " min after dawn"
        : "On " + (-page.offset) + " min after dusk, off " + (-page.offset) + " min before dawn"

      Stepper {
        anchors.verticalCenter: parent.verticalCenter
        view: page.view
        text: (page.offset > 0 ? "+" : "") + page.offset + " min"
        minusAction: "offset-minus"
        plusAction: "offset-plus"
        atMin: page.offset <= -120
        atMax: page.offset >= 120
        onMinus: page.w.stepSetting("darkHoursOffset", page.offset, -5, -120, 120)
        onPlus: page.w.stepSetting("darkHoursOffset", page.offset, 5, -120, 120)
      }
    }
  }

  // ---- Location ----
  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "LOCATION"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    ButtonGroup {
      focusable: false
      options: [{ "value": "zone", "label": "Timezone" }, { "value": "custom", "label": "Custom" }]
      value: page.customLocation ? "custom" : "zone"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
      fontSize: Style.font.bodySmall
      cursorIndex: page.view.hasCursorOn("loc-zone") ? 0 : (page.view.hasCursorOn("loc-custom") ? 1 : -1)
      onChanged: function(value) { page.chooseLocation(value === "custom") }
      onHovered: function(index, h) { page.view.hoverAction(index === 0 ? "loc-zone" : "loc-custom", h) }
    }

    TextField {
      id: locationField
      visible: page.customLocation
      width: parent.width
      text: page.w.darkHoursLocation
      placeholderText: "48.21, 16.37"
      foreground: page.view.fg
      font.family: page.view.fontFamily
      font.pixelSize: Style.font.body
      onAccepted: {
        page.saveLocation()
        page.view.restoreFocus()
      }
      onEditingFinished: page.saveLocation()
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: {
        var t = page.twilight
        if (page.customLocation)
          return "Latitude, longitude; south and west negative. Enter saves."
            + (t && t.source === "setting" ? " Using " + t.lat + ", " + t.lon + "." : "")
        if (!t) return "Your timezone's city"
        return t.source + ": " + t.lat + ", " + t.lon
          + ". A wide timezone can be far off; Custom sets your own."
      }
      color: page.view.dim
      font.family: page.view.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  PanelSeparator { foreground: page.view.fg }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    text: {
      var kbs = page.w.backlitKeyboards
      if (kbs.length === 0) return "No backlit keyboard yet. Dark hours start with the first one."
      var on = page.w.darkKeyboards.map(function(d) { return d.name })
      var skipped = []
      for (var i = 0; i < kbs.length; i++)
        if (page.w.darkSkipped(kbs[i]) && skipped.indexOf(kbs[i].name) < 0) skipped.push(kbs[i].name)
      return (on.length > 0 ? "Switches " + on.join(", ") + "." : "Switches no keyboard.")
        + (skipped.length > 0 ? " Skipped in its drawer: " + skipped.join(", ") + "." : "")
    }
    color: page.view.dim
    font.family: page.view.fontFamily
    font.pixelSize: Style.font.caption
  }
}
