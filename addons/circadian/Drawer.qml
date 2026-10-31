import QtQuick
import qs.Ui
import "../.."

// Circadian in a backlit keyboard's drawer: follow or skip it, and the way to
// its page. Built in, so it also gets the panel (host.view) and its service
// (host.service), and takes part in the keyboard cursor.
OptionRow {
  id: row

  // Set at creation by the drawer (see addons/ADDONS.md).
  property var device
  property var host

  readonly property var service: host.service
  // The device as Solaarchy has it, backlight included.
  readonly property var keyboard: {
    var list = service.backlit
    for (var i = 0; i < list.length; i++)
      if (String(list[i].id) === device.id) return list[i]
    return null
  }
  readonly property bool follows: !!keyboard && service.follows(keyboard)
  readonly property string followAction: "circadian.follow:" + device.id

  view: host.view
  glyph: "󰖔"
  label: "Circadian"
  caption: !follows ? "Skipped for this keyboard"
    : service.timesText !== "" ? "Light " + service.timesText
    : "Light on at dusk, off at dawn"

  ToggleSwitch {
    anchors.verticalCenter: parent.verticalCenter
    checked: row.follows
    foreground: row.host.foreground
    hasCursor: row.host.view.hasCursorOn(row.followAction)
    onToggled: row.host.view.runAction(row.followAction)
    onHovered: function(h) { row.host.view.hoverAction(row.followAction, h) }
  }

  PanelActionButton {
    anchors.verticalCenter: parent.verticalCenter
    iconText: "󰅂"
    tooltipText: "Times, timing and location"
    foreground: row.host.foreground
    fontFamily: row.host.fontFamily
    hasCursor: row.host.view.hasCursorOn("addon-page:circadian")
    onClicked: row.host.view.runAction("addon-page:circadian")
    onHovered: function(h) { row.host.view.hoverAction("addon-page:circadian", h) }
  }
}
