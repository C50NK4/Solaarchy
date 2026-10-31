import QtQuick
import qs.Commons
import qs.Ui
import "../.."

// Circadian's page: today as a 24-hour strip (filled = keyboard light on),
// the timing against civil dusk and dawn, and where those are worked out for.
Column {
  id: page

  // Set at creation by PanelContent.qml: the add-on's service, the bar
  // widget, and the panel.
  property var service
  property var w
  property var view

  // Omarchy's location or Custom. Custom stays picked while its field is
  // still empty; the page is built fresh each time, so it starts as saved.
  property bool customLocation: service.location !== ""
  readonly property var twilight: service.twilight
  readonly property int offset: service.offset
  // On, with a keyboard that follows it.
  readonly property bool active: service.keyboards.length > 0

  width: parent ? parent.width : 0
  spacing: Style.space(14)

  function chooseLocation(custom) {
    customLocation = custom
    if (!custom) {
      if (service.location !== "") w.saveSetting("circadianLocation", "")
      view.restoreFocus()
    } else {
      locationField.forceActiveFocus()
    }
  }

  function saveLocation() {
    var text = locationField.text.trim()
    if (text !== service.location) w.saveSetting("circadianLocation", text)
  }

  Connections {
    target: page.service
    function onLocationModeRequested(custom) { page.chooseLocation(custom) }
  }

  PageHeader {
    view: page.view
    title: "Circadian"
    backTooltip: page.view.backPage === "settings" ? "Back to settings" : "Back to devices"

    ToggleSwitch {
      anchors.verticalCenter: parent.verticalCenter
      checked: page.service.on
      foreground: page.view.fg
      hasCursor: page.view.hasCursorOn("circadian.toggle")
      onToggled: page.view.runAction("circadian.toggle")
      onHovered: function(h) { page.view.hoverAction("circadian.toggle", h) }
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
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: "Your keyboard's light goes on at dusk and off at dawn: when the sun is 6° below the horizon."
      color: page.view.dim
      font.family: page.view.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      visible: !page.twilight
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: page.service.error !== "" ? page.service.error : "Working out dusk and dawn…"
      color: page.service.error !== "" ? page.view.urgent : page.view.dim
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

      // Switch times over the strip, with the bulb's own glyphs: on where a
      // lit span starts, off where one ends; midnight is not a switch.
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
          text: (modelData.on ? "󰛨 " : "󰌶 ") + page.service.clockText(modelData.minute)
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

    // What the sky does, without the offset: "light" alone read as the
    // keyboard's light.
    Text {
      visible: !!page.twilight
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: !page.twilight ? ""
        : (page.twilight.outsideDark ? "Dark outside" : "Daylight outside")
          + (page.twilight.outsideUntil ? " until " + page.service.timeText(page.twilight.outsideUntil) : " all day")
          + (page.active ? "." : !page.service.on ? ". Circadian is off." : ". No keyboard follows it yet.")
      color: page.view.dim
      font.family: page.view.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // ---- Timing ----
  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "TIMING"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    OptionRow {
      view: page.view
      glyph: "󰔛"
      label: page.offset === 0 ? "At dusk and dawn" : (page.offset > 0 ? "Lit longer" : "Lit shorter")
      caption: page.offset === 0 ? "On at dusk, off at dawn"
        : page.offset > 0 ? "On " + page.offset + " min before dusk, off " + page.offset + " min after dawn"
        : "On " + (-page.offset) + " min after dusk, off " + (-page.offset) + " min before dawn"

      Stepper {
        anchors.verticalCenter: parent.verticalCenter
        view: page.view
        text: (page.offset > 0 ? "+" : "") + page.offset + " min"
        minusAction: "circadian.offset-minus"
        plusAction: "circadian.offset-plus"
        atMin: page.offset <= -120
        atMax: page.offset >= 120
        onMinus: page.view.runAction("circadian.offset-minus")
        onPlus: page.view.runAction("circadian.offset-plus")
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
      options: [{ "value": "omarchy", "label": "Omarchy" }, { "value": "custom", "label": "Custom" }]
      value: page.customLocation ? "custom" : "omarchy"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
      fontSize: Style.font.bodySmall
      cursorIndex: page.view.hasCursorOn("circadian.loc-omarchy") ? 0 : (page.view.hasCursorOn("circadian.loc-custom") ? 1 : -1)
      onChanged: function(value) { page.chooseLocation(value === "custom") }
      onHovered: function(index, h) { page.view.hoverAction(index === 0 ? "circadian.loc-omarchy" : "circadian.loc-custom", h) }
    }

    TextField {
      id: locationField
      visible: page.customLocation
      width: parent.width
      text: page.service.location
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
            + (t && t.source === "custom" ? " Using " + t.lat + ", " + t.lon + "." : "")
        if (!t) return "The location set in Omarchy, else your timezone's city."
        if (t.source === "omarchy")
          return "Omarchy's weather location" + (t.place !== "" ? ", " + t.place : "") + ": " + t.lat + ", " + t.lon + "."
        var city = String(t.place).split("/").pop().replace(/_/g, " ")
        return "Your timezone's city, " + city + ": " + t.lat + ", " + t.lon
          + ". Set a location for Omarchy's weather, or Custom, if you live far from it."
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
      var kbs = page.service.backlit
      if (kbs.length === 0) return "No backlit keyboard yet. Circadian starts with the first one."
      var on = page.service.keyboards.map(function(d) { return d.name })
      var skipped = kbs.filter(page.service.skipped).map(function(d) { return d.name })
      return (on.length > 0 ? "Switches " + on.join(", ") + "." : "Switches no keyboard.")
        + (skipped.length > 0 ? " Skipped in its drawer: " + skipped.join(", ") + "." : "")
    }
    color: page.view.dim
    font.family: page.view.fontFamily
    font.pixelSize: Style.font.caption
  }
}
