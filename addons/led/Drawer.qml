import QtQuick
import qs.Commons
import qs.Ui
import "../.."

// LED Effects in a mouse's drawer: one cycler that moves every zone to the same next
// effect (Primary and Logo stay in lock-step), and a hue slider for the
// effects that carry a color (Static, Breathe). The master switch is the row
// bulb on the device's row; the drawer stays open while it is off, and a
// change made there turns the bulb back on (the service re-enables the
// control with the write). Built in, so it also gets the panel (host.view)
// and its service (host.service), and takes part in the keyboard cursor. All
// the state lives in the service; this row is rebuilt whenever the device or
// the drawer changes, so it only ever reads.
Column {
  id: drawer
  width: parent.width
  spacing: Style.space(6)

  // Set at creation by the drawer (see addons/ADDONS.md).
  property var device
  property var host

  readonly property var service: host.service
  readonly property string id: String(device.id)
  // The live device's online state, with the snapshot as a fallback: the
  // drawer may be shown a moment before a fresh core read has landed.
  readonly property bool online: host.device ? !!host.device.online : !!device.online
  readonly property bool busy: service ? service.busyFor(id) : false

  OptionRow {
    id: row
    view: host.view
    glyph: "󰛨"
    label: "LED Effects"
    // The service's message (a failed write) is urgent; otherwise the last
    // read: the linked effect while control is on, the state while off.
    caption: service && service.message !== "" ? service.message
      : !service || (!online || service.reading) && !service.hasZones(id) ? "No LED state read yet"
      : !service.hasZones(id) ? service.noStateHint
      : service.controlOn(id) ? "Effect: " + (service.linkedEffect(id) || "—")
      : "Control off"
    captionUrgent: service && service.message !== ""

    // The one linked cycler: every click moves all zones to the same next
    // effect, so a pair that drifted apart re-syncs; the current effect is
    // named in the caption.
    PanelActionButton {
      anchors.verticalCenter: parent.verticalCenter
      fontSize: Style.font.body
      iconText: "↻"
      foreground: host.foreground
      hoverColor: host.foreground
      fontFamily: host.fontFamily
      enabled: online && !drawer.busy && !!service && service.hasZones(id)
      hasCursor: host.view.hasCursorOn("led.effect:" + id)
      tooltipText: drawer.busy
        ? "Changing the LED effect…"
        : "LED effect: click to change all zones ("
          + ((service && service.linkedEffect(id)) || "—") + ")"
          + (service && !service.controlOn(id) ? "\nLED control turns back on" : "")
      onClicked: host.view.runAction("led.effect:" + id)
      onHovered: function(h) { host.view.hoverAction("led.effect:" + id, h) }
    }
  }

  // The hue slider, the color-picker pattern: a rainbow spectrum track (red
  // at both ends — hue 0 and 360 are the same color) with the knob painted
  // the hue under it. Shown only while the linked effect carries a color
  // param, so Static and Breathe get a color and Cycle and Disabled don't.
  // Drawn with a Canvas of 1px hue strips, not a Gradient: on this Qt 6.12
  // build the gradient renders solid white. The Canvas is declared before the
  // slider, so the spectrum paints under it, and the slider's own track and
  // fill stay transparent so only the knob shows.
  Item {
    id: hueRow
    width: parent.width
    visible: service ? service.zoneHue(id) >= 0 : false
    implicitHeight: hueSlider.implicitHeight

    Rectangle {
      id: hueTrack
      anchors.left: hueSlider.left
      anchors.right: hueSlider.right
      anchors.verticalCenter: hueSlider.verticalCenter
      height: hueSlider.trackHeight
      radius: height / 2
      clip: true
      color: "transparent"
      Canvas {
        anchors.fill: parent
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          for (var x = 0; x < width; x++) {
            ctx.fillStyle = service ? service.hueToColor(x / width * 360) : "transparent"
            ctx.fillRect(x, 0, 1, height)
          }
        }
      }
    }

    PanelSlider {
      id: hueSlider
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      minimum: 0
      maximum: 360
      step: 5
      integer: true
      value: service ? Math.max(0, service.zoneHue(id)) : 0
      trackColor: "transparent"
      fillColor: "transparent"
      knobColor: service ? service.hueToColor(hueSlider.liveValue) : "transparent"
      onReleased: function(hue) {
        if (!service || !online || drawer.busy) {
          hueSlider.liveValue = hueSlider.value  // rejected: snap back
          return
        }
        service.setColor(host.device || device, service.hueToRgb(Math.round(hue)))
      }
    }
  }
}
