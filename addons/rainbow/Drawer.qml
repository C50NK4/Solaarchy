import QtQuick
import qs.Commons
import qs.Ui

// Rainbow LED, an experimental built-in: a greyed mock-up of a colour control,
// drawn only with what any add-on's drawer gets (see ../ADDONS.md). It
// switches nothing; it is here to try a second add-on alongside Circadian.
Column {
  // Set at creation by the drawer.
  property var device
  property var host

  width: parent ? parent.width : 0
  spacing: Style.space(6)
  // Greyed: nothing here is live.
  opacity: 0.4
  enabled: false

  // The glyph column matches the rows above it.
  Row {
    spacing: Style.space(4)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(24)
      textFormat: Text.PlainText
      text: "󰍄"
      color: host.foreground
      font.family: host.fontFamily
      font.pixelSize: Style.font.icon
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "Rainbow LED · mock-up"
      color: host.foreground
      font.family: host.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  // Where a hue slider would go.
  Rectangle {
    width: parent.width
    height: Style.space(10)
    radius: height / 2
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: "#ff0000" }
      GradientStop { position: 0.17; color: "#ffff00" }
      GradientStop { position: 0.33; color: "#00ff00" }
      GradientStop { position: 0.5; color: "#00ffff" }
      GradientStop { position: 0.67; color: "#0000ff" }
      GradientStop { position: 0.83; color: "#ff00ff" }
      GradientStop { position: 1.0; color: "#ff0000" }
    }
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    text: "Colour effects for " + device.name + " would go here. An experimental mock-up: it changes nothing."
    color: host.dim
    font.family: host.fontFamily
    font.pixelSize: Style.font.caption
  }
}
