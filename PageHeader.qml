import QtQuick
import qs.Commons
import qs.Ui

// Back button and title of a sub-page, with optional controls at the right.
Item {
  id: header

  property var view
  property string title: ""
  property string backTooltip: "Back"
  default property alias controls: slot.data

  width: parent ? parent.width : 0
  implicitHeight: Math.max(backButton.implicitHeight, titleText.implicitHeight, slot.implicitHeight)

  PanelActionButton {
    id: backButton
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    iconText: "󰁍"
    tooltipText: header.backTooltip
    foreground: header.view.fg
    fontFamily: header.view.fontFamily
    hasCursor: header.view.hasCursorOn("back")
    onClicked: header.view.goBack()
    onHovered: function(h) { header.view.hoverAction("back", h) }
  }

  Text {
    id: titleText
    anchors.left: backButton.right
    anchors.leftMargin: Style.space(8)
    anchors.right: slot.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: header.title
    color: header.view.fg
    font.family: header.view.fontFamily
    font.pixelSize: Style.font.title
    font.bold: true
    elide: Text.ElideRight
  }

  Row {
    id: slot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)
  }
}
