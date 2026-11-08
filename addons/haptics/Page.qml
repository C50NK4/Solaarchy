import QtQuick
import qs.Commons
import qs.Ui
import "../.."
import "events.js" as Events

// Haptics' page: each haptic device's level, the events that buzz with the
// waveform each plays (a row opens its waveform tiles in place), and quiet in
// fullscreen. Picks apply to every haptic device.
Column {
  id: page

  // Set at creation by PanelContent.qml: the add-on's service, the bar
  // widget, and the panel.
  property var service
  property var w
  property var view

  width: parent ? parent.width : 0
  spacing: Style.space(14)

  // The page is built fresh each time it opens: start with every row shut.
  Component.onCompleted: service.expanded = ""

  PageHeader {
    view: page.view
    title: "Haptics"
    backTooltip: page.view.backPage === "settings" ? "Back to settings" : "Back to devices"

    ToggleSwitch {
      anchors.verticalCenter: parent.verticalCenter
      checked: page.service.on
      foreground: page.view.fg
      hasCursor: page.view.hasCursorOn("haptics.toggle")
      onToggled: page.view.runAction("haptics.toggle")
      onHovered: function(h) { page.view.hoverAction("haptics.toggle", h) }
    }
  }

  PanelSeparator { foreground: page.view.fg }

  Caption {
    text: !page.service.on ? "Haptics is off: no pulses, and no player running."
      : page.service.haptic.length === 0 ? "No device with a haptic motor yet. The MX Master 4 has one."
      : "A pulse on your mouse for each event you pick. Picking a waveform plays it."
  }

  Caption {
    visible: page.service.on && page.service.error !== ""
    text: page.service.error
    urgent: true
  }

  // ---- Level ----
  Column {
    visible: page.service.on && page.service.haptic.length > 0
    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader {
      text: "LEVEL"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    Repeater {
      model: page.service.haptic

      Column {
        required property var modelData
        width: parent.width
        spacing: Style.space(4)

        Caption {
          visible: page.service.haptic.length > 1
          text: modelData.name
        }

        LevelButtons {
          view: page.view
          service: page.service
          device: modelData
        }
      }
    }
  }

  EventSection { title: "ALERTS"; group: "alerts" }

  EventSection { title: "DESKTOP"; group: "desktop" }

  OptionRow {
    view: page.view
    label: "Quiet in fullscreen"
    caption: "No desktop events while a game or video is fullscreen"

    ToggleSwitch {
      anchors.verticalCenter: parent.verticalCenter
      checked: page.service.pauseFullscreen
      foreground: page.view.fg
      hasCursor: page.view.hasCursorOn("haptics.pause")
      onToggled: page.view.runAction("haptics.pause")
      onHovered: function(h) { page.view.hoverAction("haptics.pause", h) }
    }
  }

  // ---- Per app ----
  Column {
    width: parent.width
    spacing: Style.space(6)

    PanelSectionHeader {
      text: "PER APP"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    TextField {
      id: appsField
      width: parent.width
      text: page.service.appsText
      placeholderText: "slack=knock, spotify=off"
      foreground: page.view.fg
      font.family: page.view.fontFamily
      font.pixelSize: Style.font.bodySmall
      onAccepted: page.view.restoreFocus()
      onEditingFinished: {
        if (text.trim() !== page.service.appsText) page.w.saveSetting("hapticNotificationApps", text.trim())
      }
    }

    Caption {
      text: "A notification's app name, then a waveform or off. These come before All notifications. Enter saves."
    }
  }

  PanelSeparator { foreground: page.view.fg }

  Caption {
    text: "From a script or a keybind: " + page.service.addon.dir.replace(page.w.home, "~") + "/haptics.py play completed"
  }

  // A dim line of text, or an urgent one.
  component Caption: Text {
    property bool urgent: false
    width: parent ? parent.width : 0
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: urgent ? page.view.urgent : page.view.dim
    font.family: page.view.fontFamily
    font.pixelSize: Style.font.caption
  }

  // A header over one row per event, each showing the waveform it plays. A
  // row opens the waveform tiles under it.
  component EventSection: Column {
    id: section
    property string title: ""
    property string group: ""
    width: parent ? parent.width : 0
    spacing: Style.space(2)

    PanelSectionHeader {
      text: section.title
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    Repeater {
      model: Events.inGroup(section.group)

      Column {
        id: event
        required property var modelData
        readonly property string action: "haptics.event-" + modelData.setting
        readonly property string wave: page.service.waveSetting(modelData.setting)
        readonly property bool open: page.service.expanded === modelData.setting
        width: section.width
        spacing: Style.space(4)

        Item {
          width: parent.width
          implicitHeight: Style.space(26)

          Button {
            anchors.fill: parent
            foreground: page.view.fg
            fontFamily: page.view.fontFamily
            hasCursor: page.view.hasCursorOn(event.action)
            tooltipText: event.modelData.description
            onClicked: page.view.runAction(event.action)
            onHovered: function(h) { page.view.hoverAction(event.action, h) }
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.right: waveLabel.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: event.modelData.label
            color: page.view.fg
            font.family: page.view.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            id: waveLabel
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: Events.labelFor(event.wave) + (event.open ? "  󰅀" : "  󰅂")
            color: event.wave === "off" ? page.view.dim : page.view.fg
            font.family: page.view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // Off, then every waveform the devices can play, two to a row.
        Grid {
          id: tiles
          visible: event.open
          width: parent.width
          columns: 2
          columnSpacing: Style.space(4)
          rowSpacing: Style.space(4)
          bottomPadding: Style.space(6)
          readonly property real tileWidth: Math.floor((width - columnSpacing) / 2)

          Repeater {
            model: event.open ? [{ "key": "off", "label": "Off" }].concat(page.service.waveforms) : []

            Button {
              required property var modelData
              readonly property string action: "haptics.wave-" + modelData.key
              width: tiles.tileWidth
              text: modelData.label
              bordered: true
              selected: event.wave === modelData.key
              foreground: page.view.fg
              fontFamily: page.view.fontFamily
              fontSize: Style.font.bodySmall
              hasCursor: page.view.hasCursorOn(action)
              tooltipText: modelData.key === "off" ? "No pulse for this event" : "Use it, and feel it now"
              onClicked: page.view.runAction(action)
              onHovered: function(h) { page.view.hoverAction(action, h) }
            }
          }
        }
      }
    }
  }
}
