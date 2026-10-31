import QtQuick
import qs.Commons
import qs.Ui

// − value + for a number setting. Both buttons are keyboard-cursor targets,
// so a stepper needs no text field and no focus handling.
Row {
  id: stepper

  property var view
  property string text: ""
  property string minusAction: ""
  property string plusAction: ""
  // At a limit the button stays a cursor target but dims.
  property bool atMin: false
  property bool atMax: false
  property real valueWidth: Style.space(58)

  signal minus()
  signal plus()

  spacing: Style.space(2)

  PanelActionButton {
    anchors.verticalCenter: parent.verticalCenter
    iconText: "󰍴"
    fontSize: Style.font.body
    foreground: stepper.atMin ? stepper.view.dim : stepper.view.fg
    hoverColor: stepper.view.fg
    fontFamily: stepper.view.fontFamily
    hasCursor: stepper.view.hasCursorOn(stepper.minusAction)
    onClicked: stepper.minus()
    onHovered: function(h) { stepper.view.hoverAction(stepper.minusAction, h) }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    width: stepper.valueWidth
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
    text: stepper.text
    color: stepper.view.fg
    font.family: stepper.view.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  PanelActionButton {
    anchors.verticalCenter: parent.verticalCenter
    iconText: "󰐕"
    fontSize: Style.font.body
    foreground: stepper.atMax ? stepper.view.dim : stepper.view.fg
    hoverColor: stepper.view.fg
    fontFamily: stepper.view.fontFamily
    hasCursor: stepper.view.hasCursorOn(stepper.plusAction)
    onClicked: stepper.plus()
    onHovered: function(h) { stepper.view.hoverAction(stepper.plusAction, h) }
  }
}
