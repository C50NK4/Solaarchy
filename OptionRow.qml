import QtQuick
import qs.Commons
import qs.Ui

// One setting: an optional glyph, a label over a caption, and its controls
// (switches, steppers, small buttons) at the right edge.
Item {
  id: row

  // Panel.qml: colours, font and the keyboard cursor.
  property var view
  property string glyph: ""
  property string label: ""
  property string caption: ""
  property bool captionUrgent: false
  default property alias controls: slot.data

  width: parent ? parent.width : 0
  implicitHeight: Math.max(labels.implicitHeight, slot.implicitHeight, glyphText.implicitHeight)

  Text {
    id: glyphText
    visible: row.glyph !== ""
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: visible ? Style.space(24) : 0
    textFormat: Text.PlainText
    text: row.glyph
    color: row.view.fg
    font.family: row.view.fontFamily
    font.pixelSize: Style.font.icon
  }

  Column {
    id: labels
    anchors.left: glyphText.right
    anchors.leftMargin: glyphText.visible ? Style.space(4) : 0
    anchors.right: slot.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: row.label
      color: row.view.fg
      font.family: row.view.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      visible: row.caption !== ""
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: row.caption
      color: row.captionUrgent ? row.view.urgent : row.view.dim
      font.family: row.view.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Row {
    id: slot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)
  }
}
