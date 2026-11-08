import QtQuick
import qs.Commons
import qs.Ui
import "../.."
import "events.js" as Events

// Haptics in a haptic device's drawer: its level, and the way to the page
// with the events that buzz. Built in, so it also gets the panel (host.view)
// and its service (host.service), and takes part in the keyboard cursor.
Column {
  id: drawer

  // Set at creation by the drawer (see addons/ADDONS.md).
  property var device
  property var host

  readonly property var service: host.service
  readonly property int level: service.level(device)

  width: parent ? parent.width : 0
  spacing: Style.space(8)

  OptionRow {
    view: drawer.host.view
    glyph: "󰕦"
    label: "Haptics"
    caption: drawer.level < 0 ? (drawer.device.online ? "Reading its level…" : "Level shows once it is awake")
      : drawer.level === 0 ? "Off on this device: nothing plays"
      : "Level " + drawer.level + " · " + drawer.service.eventsText

    PanelActionButton {
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅂"
      tooltipText: "Events and waveforms"
      foreground: drawer.host.foreground
      fontFamily: drawer.host.fontFamily
      hasCursor: drawer.host.view.hasCursorOn("addon-page:haptics")
      onClicked: drawer.host.view.runAction("addon-page:haptics")
      onHovered: function(h) { drawer.host.view.hoverAction("addon-page:haptics", h) }
    }
  }

  LevelButtons {
    view: drawer.host.view
    service: drawer.service
    device: drawer.device
  }
}
