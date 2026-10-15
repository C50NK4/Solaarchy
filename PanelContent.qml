import QtQuick
import qs.Commons
import qs.Ui
import "haptics.js" as Haptics
import "icons.js" as Icons

// Solaarchy panel body. Pages that swap in place: the devices, the bar icon
// picker opened from the palette button next to Refresh, the haptics of one
// device, opened from the button next to its name, and from there the
// waveform picker for one event.
Item {
  id: content

  // Set once, at creation, by Panel.qml: the bar widget holding the device
  // state, and the panel for colours, page and keyboard-cursor state.
  property var w
  property var view

  implicitHeight: content.view.page === "icons" ? iconsPage.implicitHeight
    : content.view.page === "haptics" ? hapticsPage.implicitHeight
    : content.view.page === "wave" ? wavePage.implicitHeight
    : mainPage.implicitHeight

  // ================= Devices =================
  Column {
    id: mainPage
    visible: content.view.page === "main"
    width: parent.width
    spacing: Style.space(14)

    PanelHero {
      width: parent.width
      foreground: content.view.fg
      fontFamily: content.view.fontFamily
      title: "Solaarchy"
      meta: content.w.metaText
      iconComponent: Component {
        IconMark {
          iconId: content.w.currentIcon.id
          iconData: content.w.currentIcon.custom ? content.w.currentIcon : null
          height: Icons.fitHeight(content.w.currentIcon, Style.font.display)
          color: content.w.anyLow ? content.view.urgent : content.view.fg
          Behavior on color { ColorAnimation { duration: 200 } }
        }
      }
      trailingControl: Component {
        Row {
          spacing: Style.space(4)

          PanelActionButton {
            iconText: "󰏘"
            tooltipText: "Bar icon"
            foreground: content.view.fg
            fontFamily: content.view.fontFamily
            hasCursor: content.view.hasCursorOn("icons")
            onClicked: content.view.showPage("icons")
            onHovered: function(h) { content.view.hoverAction("icons", h) }
          }

          PanelActionButton {
            iconText: "󰑐"
            tooltipText: content.w.refreshing ? "Refreshing…" : "Refresh"
            foreground: content.view.fg
            fontFamily: content.view.fontFamily
            enabled: !content.w.refreshing
            hasCursor: content.view.hasCursorOn("refresh")
            onClicked: content.w.refresh()
            onHovered: function(h) { content.view.hoverAction("refresh", h) }
          }
        }
      }
    }

    PanelSeparator { foreground: content.view.fg }

    Column {
      width: parent.width
      spacing: Style.space(12)

      Item {
        width: parent.width
        implicitHeight: Math.max(devicesHeader.implicitHeight, solaarButton.implicitHeight)

        PanelSectionHeader {
          id: devicesHeader
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "DEVICES"
          foreground: content.view.fg
          fontFamily: content.view.fontFamily
        }

        // Same hover and cursor treatment as a PanelActionButton, with a label.
        BorderSurface {
          id: solaarButton
          readonly property bool hot: solaarMouse.containsMouse || content.view.hasCursorOn("solaar")
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: solaarRow.implicitWidth + Style.space(12)
          implicitHeight: Math.max(Style.space(22), solaarRow.implicitHeight + Style.space(4))
          radius: Style.cornerRadius
          color: hot ? Style.hoverFillFor(content.view.fg, content.view.fg) : "transparent"
          borderSpec: Border.none()

          Behavior on color { ColorAnimation { duration: 60 } }

          Row {
            id: solaarRow
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Solaar"
              color: content.view.fg
              font.family: content.view.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            IconMark {
              anchors.verticalCenter: parent.verticalCenter
              iconId: "solaar"
              height: Style.font.body
              color: content.view.fg
            }
          }

          MouseArea {
            id: solaarMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: content.view.hoverAction("solaar", containsMouse)
            onClicked: content.w.openSolaar()
          }

          PanelToolTip {
            visible: solaarMouse.containsMouse
            text: "Open Solaar: pairing, buttons, DPI and more (middle-click the bar icon)"
            fontFamily: content.view.fontFamily
          }
        }
      }

      Text {
        visible: content.w.devices.length === 0
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: content.w.lastError !== "" ? content.w.lastError
          : (!content.w.loaded ? "Reading devices…"
            : content.w.receivers.length > 0 ? "No devices paired with " + content.w.receivers.join(", ")
            : "No Logitech receiver or device connected")
        color: content.w.lastError !== "" ? content.view.urgent : content.view.dim
        font.family: content.view.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        model: content.w.devices

        Column {
          id: deviceItem
          required property var modelData
          // Urgent-red only applies to a fresh, currently-connected reading;
          // a stale or offline device keeps its last percentage on screen
          // but never as an urgent color that could otherwise stay red
          // indefinitely once the device stops being read.
          readonly property bool live: !modelData.stale && modelData.online
          readonly property bool low: live && !!modelData.battery && modelData.battery.level <= content.w.lowThreshold
          readonly property real fraction: modelData.battery ? Math.max(0, Math.min(1, modelData.battery.level / 100)) : 0
          readonly property bool hasBacklight: !!modelData.backlight
          readonly property bool hasHaptics: !!modelData.haptics
          readonly property bool lightOn: content.w.backlightOn(modelData)
          readonly property real labelsGap: Style.space(8)
          width: parent.width
          spacing: Style.space(7)
          opacity: live ? 1.0 : 0.6

          Item {
            width: parent.width
            implicitHeight: Math.max(kindGlyph.implicitHeight, labels.implicitHeight, percent.implicitHeight)

            Text {
              id: kindGlyph
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(24)
              text: content.w.kindIcon(deviceItem.modelData.kind)
              color: content.view.fg
              font.family: content.view.fontFamily
              font.pixelSize: Style.font.iconLarge
            }

            Column {
              id: labels
              anchors.left: kindGlyph.right
              anchors.leftMargin: Style.space(8)
              anchors.right: percent.left
              anchors.rightMargin: deviceItem.labelsGap
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              // Name, with the device's buttons in the space after it: the
              // backlight switch on keyboards, haptics on devices that buzz.
              Item {
                width: parent.width
                implicitHeight: Math.max(nameText.implicitHeight, deviceButtons.visible ? deviceButtons.implicitHeight : 0)

                Text {
                  id: nameText
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, parent.width - (deviceButtons.visible ? deviceButtons.width + Style.space(8) : 0))
                  textFormat: Text.PlainText
                  text: deviceItem.modelData.name
                  color: content.view.fg
                  font.family: content.view.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Row {
                  id: deviceButtons
                  // Centred in the free space between the end of the name and
                  // the percentage, which starts labelsGap past this row.
                  readonly property real freeStart: nameText.width
                  readonly property real freeEnd: parent.width + deviceItem.labelsGap
                  visible: deviceItem.hasBacklight || deviceItem.hasHaptics
                  x: Math.round(freeStart + Math.max(Style.space(4), (freeEnd - freeStart - width) / 2))
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  PanelActionButton {
                    id: bulb
                    visible: deviceItem.hasBacklight
                    fontSize: Style.font.body
                    iconText: deviceItem.lightOn ? "󰛨" : "󰌶"
                    foreground: deviceItem.lightOn ? content.view.fg : content.view.dim
                    hoverColor: content.view.fg
                    fontFamily: content.view.fontFamily
                    enabled: !content.w.backlightBusy && deviceItem.modelData.online
                    hasCursor: content.view.hasCursorOn("backlight:" + deviceItem.modelData.id)
                    tooltipText: content.w.backlightBusyFor(deviceItem.modelData)
                      ? (deviceItem.lightOn ? "Turning backlight on…" : "Turning backlight off…")
                      : "Backlight " + (deviceItem.lightOn ? "on" : "off") + ": click to turn "
                        + (deviceItem.lightOn ? "off" : "on")
                    onClicked: content.w.toggleBacklight(deviceItem.modelData)
                    onHovered: function(h) { content.view.hoverAction("backlight:" + deviceItem.modelData.id, h) }
                  }

                  PanelActionButton {
                    visible: deviceItem.hasHaptics
                    fontSize: Style.font.body
                    iconText: "󰕦"
                    foreground: content.w.hapticLevel(deviceItem.modelData) > 0 ? content.view.fg : content.view.dim
                    hoverColor: content.view.fg
                    fontFamily: content.view.fontFamily
                    hasCursor: content.view.hasCursorOn("haptics:" + deviceItem.modelData.id)
                    tooltipText: "Haptics: level and waveforms"
                    onClicked: content.view.showHaptics(deviceItem.modelData)
                    onHovered: function(h) { content.view.hoverAction("haptics:" + deviceItem.modelData.id, h) }
                  }
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: content.w.statusText(deviceItem.modelData)
                color: deviceItem.low ? content.view.urgent : content.view.dim
                font.family: content.view.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Text {
              id: percent
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: (deviceItem.modelData.battery && deviceItem.modelData.battery.charging ? "󱐋 " : "")
                + content.w.percentText(deviceItem.modelData)
              color: deviceItem.low ? content.view.urgent : content.view.fg
              font.family: content.view.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
          }

          // Charge bar
          Item {
            width: parent.width
            implicitHeight: Style.space(6)
            visible: !!deviceItem.modelData.battery

            Rectangle {
              id: track
              anchors.fill: parent
              radius: height / 2
              color: Qt.rgba(content.view.fg.r, content.view.fg.g, content.view.fg.b, 0.12)
            }

            Rectangle {
              anchors.left: track.left
              anchors.verticalCenter: track.verticalCenter
              height: track.height
              radius: track.radius
              width: Math.max(track.height, track.width * deviceItem.fraction)
              color: deviceItem.low ? content.view.urgent : content.view.fg
              Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
              Behavior on color { ColorAnimation { duration: 220 } }

              SequentialAnimation on opacity {
                running: !!deviceItem.modelData.battery && deviceItem.modelData.battery.charging && content.view.opened
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.55; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
              }
            }
          }
        }
      }

      MessageText {
        visible: content.w.actionError !== ""
        text: content.w.actionError
        urgent: true
      }

      MessageText {
        visible: content.w.monitorError !== ""
        text: "Live updates are broken, falling back to polling: " + content.w.monitorError
        urgent: true
      }

      MessageText {
        // Shown even with no devices listed: a receiver can open fine but
        // fail to enumerate its paired devices, which is exactly the case
        // the generic "no devices" text above doesn't explain.
        visible: content.w.warnings.length > 0
        text: "Not every device could be read: " + content.w.warnings.join("; ")
      }
    }
  }

  // ================= Haptics =================
  // One device's haptic level, and the events that buzz, each with the
  // waveform it plays: a row opens the picker below.
  Column {
    id: hapticsPage
    readonly property var device: content.view.hapticDevice
    readonly property int shownLevel: Haptics.nearestLevel(content.w.hapticLevel(device))
    visible: content.view.page === "haptics"
    width: parent.width
    spacing: Style.space(14)

    Item {
      width: parent.width
      implicitHeight: Math.max(hapticsBack.implicitHeight, hapticsTitle.implicitHeight)

      PanelActionButton {
        id: hapticsBack
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰁍"
        tooltipText: "Back to devices"
        foreground: content.view.fg
        fontFamily: content.view.fontFamily
        hasCursor: content.view.hasCursorOn("back")
        onClicked: content.view.back()
        onHovered: function(h) { content.view.hoverAction("back", h) }
      }

      Text {
        id: hapticsTitle
        anchors.left: hapticsBack.right
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: hapticsPage.device ? "Haptics · " + hapticsPage.device.name : "Haptics"
        color: content.view.fg
        font.family: content.view.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }
    }

    PanelSeparator { foreground: content.view.fg }

    Column {
      width: parent.width
      spacing: Style.space(8)

      PanelSectionHeader {
        text: "LEVEL"
        foreground: content.view.fg
        fontFamily: content.view.fontFamily
      }

      Row {
        id: levelRow
        width: parent.width
        spacing: content.tileGap
        readonly property int buttonWidth: Math.floor((width - spacing * (Haptics.levels.length - 1)) / Haptics.levels.length)

        Repeater {
          model: Haptics.levels

          Item {
            id: levelButton
            required property var modelData
            required property int index
            readonly property string action: "level:" + modelData.value
            readonly property bool chosen: hapticsPage.shownLevel === modelData.value
            // The last button takes the leftover pixels, so the row ends flush.
            width: index === Haptics.levels.length - 1
              ? levelRow.width - (levelRow.buttonWidth + levelRow.spacing) * index
              : levelRow.buttonWidth
            height: Style.space(30)
            opacity: content.w.hapticLevelBusy ? 0.6 : 1.0

            Button {
              anchors.fill: parent
              bordered: true
              selected: levelButton.chosen
              foreground: content.view.fg
              fontFamily: content.view.fontFamily
              hasCursor: content.view.hasCursorOn(levelButton.action)
              tooltipText: levelButton.modelData.value === 0 ? "Haptics off" : "Level " + levelButton.modelData.value
              onClicked: content.w.setHapticLevel(hapticsPage.device, levelButton.modelData.value)
              onHovered: function(h) { content.view.hoverAction(levelButton.action, h) }
            }

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: levelButton.modelData.label
              color: levelButton.chosen ? Style.selectedStateColor(content.view.fg, Color.accent) : content.view.fg
              font.family: content.view.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }

    EventSection { title: "ALERTS"; events: Haptics.inGroup("alerts") }

    EventSection { title: "DESKTOP"; events: Haptics.inGroup("desktop") }

    // Quiet in fullscreen: the whole row is the switch.
    Item {
      width: parent.width
      implicitHeight: Style.space(30)

      Button {
        anchors.fill: parent
        foreground: content.view.fg
        fontFamily: content.view.fontFamily
        hasCursor: content.view.hasCursorOn("pause")
        tooltipText: "No desktop haptics while a fullscreen window is focused (games, video). Alerts still buzz."
        onClicked: content.w.setHapticPauseFullscreen(!content.w.hapticPauseFullscreen)
        onHovered: function(h) { content.view.hoverAction("pause", h) }
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Quiet in fullscreen"
        color: content.view.fg
        font.family: content.view.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      ToggleSwitch {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        interactive: false
        checked: content.w.hapticPauseFullscreen
        foreground: content.view.fg
      }
    }

    MessageText {
      visible: content.w.hapticError !== ""
      text: content.w.hapticError
      urgent: true
    }

    MessageText {
      visible: hapticsPage.shownLevel === 0
      text: "Haptics are off on this device, so nothing plays until a level is picked."
    }

    MessageText {
      text: "Per-app notification waveforms: omarchy bar set " + content.w.moduleName
        + " hapticNotificationApps \"slack=knock, spotify=off\". From a script: "
        + content.w.hapticsPath.replace(content.w.home, "~") + " play completed"
    }
  }

  // ================= Waveform picker =================
  // The waveform for one event: Off, or a tile per waveform the device can
  // play. Picking one saves it and plays it, so choosing is also trying.
  Column {
    id: wavePage
    readonly property var event: Haptics.eventFor(content.view.hapticEvent)
    readonly property string current: content.w.waveSetting(content.view.hapticEvent)
    visible: content.view.page === "wave"
    width: parent.width
    spacing: Style.space(14)

    Item {
      width: parent.width
      implicitHeight: Math.max(waveBack.implicitHeight, waveTitle.implicitHeight)

      PanelActionButton {
        id: waveBack
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰁍"
        tooltipText: "Back to haptics"
        foreground: content.view.fg
        fontFamily: content.view.fontFamily
        hasCursor: content.view.hasCursorOn("back")
        onClicked: content.view.back()
        onHovered: function(h) { content.view.hoverAction("back", h) }
      }

      Text {
        id: waveTitle
        anchors.left: waveBack.right
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: wavePage.event ? wavePage.event.label : "Waveform"
        color: content.view.fg
        font.family: content.view.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }
    }

    PanelSeparator { foreground: content.view.fg }

    MessageText {
      visible: !!wavePage.event
      text: wavePage.event ? wavePage.event.description : ""
    }

    WaveTile {
      width: parent.width
      key: "off"
      label: "Off"
    }

    Grid {
      id: waveGrid
      width: parent.width
      columns: 2
      columnSpacing: content.tileGap
      rowSpacing: content.tileGap
      readonly property int baseWidth: Math.floor((width - columnSpacing) / 2)

      Repeater {
        model: Haptics.forDevice(content.view.hapticDevice ? content.view.hapticDevice.haptics : null)

        WaveTile {
          required property var modelData
          required property int index
          key: modelData.key
          label: modelData.label
          width: index % 2 === 1 ? waveGrid.width - waveGrid.baseWidth - waveGrid.columnSpacing : waveGrid.baseWidth
        }
      }
    }

    MessageText {
      text: "Pick one to feel it; it is saved right away."
        + (wavePage.event && wavePage.event.defaultValue !== "off"
          ? " Default: " + Haptics.labelFor(wavePage.event.defaultValue) + "." : "")
    }
  }

  // ================= Bar icon picker =================
  // Every section is a header over a full-width block of equal tiles, so all
  // tiles share one width, gap and height and line up across sections.
  Column {
    id: iconsPage
    visible: content.view.page === "icons"
    width: parent.width
    spacing: Style.space(14)

    Item {
      width: parent.width
      implicitHeight: Math.max(backButton.implicitHeight, pageTitle.implicitHeight)

      PanelActionButton {
        id: backButton
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰁍"
        tooltipText: "Back to devices"
        foreground: content.view.fg
        fontFamily: content.view.fontFamily
        hasCursor: content.view.hasCursorOn("back")
        onClicked: content.view.showPage("main")
        onHovered: function(h) { content.view.hoverAction("back", h) }
      }

      Text {
        id: pageTitle
        anchors.left: backButton.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Bar icon"
        color: content.view.fg
        font.family: content.view.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
    }

    PanelSeparator { foreground: content.view.fg }

    IconSection {
      title: "SOLAAR"
      icons: [Icons.byId("solaar")]
      columns: 1
    }

    // Filled icons on the first row, their outline versions below.
    IconSection {
      title: "DEVICES"
      icons: Icons.inGroup("device", "filled").concat(Icons.inGroup("device", "outline"))
    }

    // The user's own icons, with the "+" tile always last so the section is
    // there to be found even before anything has been added.
    IconSection {
      title: "YOUR OWN"
      icons: content.w.customIcons
      addTile: true
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: content.w.iconPickError !== "" ? content.w.iconPickError
        : "Solaarchy ships no vendor logos. + picks an SVG of your own and "
          + "copies it to " + content.w.customIconDir.replace(content.w.home, "~")
          + "; it is drawn in the bar's colour, like every other icon."
      color: content.w.iconPickError !== "" ? content.view.urgent : content.view.dim
      font.family: content.view.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // A section of the haptics page: a header over one row per event, each
  // showing the waveform it plays. A row opens the waveform picker.
  component EventSection: Column {
    id: eventSection
    property string title: ""
    property var events: []
    width: parent ? parent.width : 0
    spacing: Style.space(4)

    PanelSectionHeader {
      text: eventSection.title
      foreground: content.view.fg
      fontFamily: content.view.fontFamily
    }

    Repeater {
      model: eventSection.events

      Item {
        id: eventRow
        required property var modelData
        readonly property string action: "event:" + modelData.setting
        readonly property string wave: content.w.waveSetting(modelData.setting)
        width: eventSection.width
        implicitHeight: Style.space(26)

        Button {
          anchors.fill: parent
          foreground: content.view.fg
          fontFamily: content.view.fontFamily
          hasCursor: content.view.hasCursorOn(eventRow.action)
          tooltipText: eventRow.modelData.description + " Click to choose its waveform."
          onClicked: content.view.showWavePicker(eventRow.modelData.setting)
          onHovered: function(h) { content.view.hoverAction(eventRow.action, h) }
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.right: waveLabel.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: eventRow.modelData.label
          color: content.view.fg
          font.family: content.view.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          id: waveLabel
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Haptics.labelFor(eventRow.wave) + "  ›"
          color: eventRow.wave === "off" ? content.view.dim : content.view.fg
          font.family: content.view.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  // One choice on the waveform picker.
  component WaveTile: Item {
    id: waveTile
    property string key: ""
    property string label: ""
    readonly property string action: "wave:" + key
    readonly property bool chosen: wavePage.current === key
    height: Style.space(30)

    Button {
      anchors.fill: parent
      bordered: true
      selected: waveTile.chosen
      foreground: content.view.fg
      fontFamily: content.view.fontFamily
      hasCursor: content.view.hasCursorOn(waveTile.action)
      tooltipText: waveTile.key === "off" ? "No pulse for this event" : "Feel it and use it · " + waveTile.key
      onClicked: content.w.setHapticEvent(content.view.hapticEvent, waveTile.key)
      onHovered: function(h) { content.view.hoverAction(waveTile.action, h) }
    }

    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: waveTile.label
      color: waveTile.chosen ? Style.selectedStateColor(content.view.fg, Color.accent) : content.view.fg
      font.family: content.view.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }

  // A secondary status line below the device list: dim by default, or
  // urgent for something that needs attention (a failed action, broken
  // live updates). Wraps and spans the full width like its siblings.
  component MessageText: Text {
    property bool urgent: false
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: urgent ? content.view.urgent : content.view.dim
    font.family: content.view.fontFamily
    font.pixelSize: Style.font.caption
  }

  // Tile geometry shared by every section.
  readonly property int tileColumns: 3
  readonly property real tileGap: Style.space(6)
  readonly property real tileHeight: Style.space(40)

  // A section header over a grid of icon tiles.
  component IconSection: Column {
    id: section
    property string title: ""
    property var icons: []
    // Appends the "add your own" tile after the last icon, in the next cell of
    // the same grid, so the columns stay aligned however many icons there are.
    property bool addTile: false
    property int columns: content.tileColumns
    width: parent ? parent.width : 0
    spacing: Style.space(8)

    PanelSectionHeader {
      text: section.title
      foreground: content.view.fg
      fontFamily: content.view.fontFamily
    }

    Grid {
      id: tiles
      width: parent.width
      columns: section.columns
      columnSpacing: content.tileGap
      rowSpacing: content.tileGap
      // Tiles get whole-pixel widths so their borders stay crisp. The few
      // leftover pixels go to the middle column, so every row ends exactly at
      // the section's right edge, flush with full-width tiles and separators.
      readonly property int baseWidth: Math.floor((width - columnSpacing * (columns - 1)) / columns)
      readonly property int remainder: Math.round(width - columnSpacing * (columns - 1) - baseWidth * columns)

      function widthFor(column) {
        return baseWidth + (column === Math.floor(columns / 2) ? remainder : 0)
      }

      Repeater {
        model: section.icons

        IconTile {
          required property var modelData
          required property int index
          icon: modelData
          width: tiles.widthFor(index % tiles.columns)
        }
      }

      AddIconTile {
        visible: section.addTile
        width: tiles.widthFor(section.icons.length % tiles.columns)
      }
    }
  }

  // The last tile of the custom section: opens a file dialog, and whatever is
  // chosen is copied into the icon folder and selected.
  component AddIconTile: Item {
    id: addTile
    height: content.tileHeight

    Button {
      anchors.fill: parent
      bordered: true
      foreground: content.view.fg
      fontFamily: content.view.fontFamily
      hasCursor: content.view.hasCursorOn("icon-add")
      tooltipText: "Add an SVG of your own"
      onClicked: content.w.pickCustomIcon()
      onHovered: function(h) { content.view.hoverAction("icon-add", h) }
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "+"
      color: content.view.dim
      font.family: content.view.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }
  }

  // One selectable icon. Icons keep their relative sizes (barScale), so a
  // keyboard stays shorter than a mouse, exactly as in the bar.
  component IconTile: Item {
    id: tile
    property var icon: null
    readonly property bool chosen: !!icon && content.w.currentIcon.id === icon.id
    readonly property string action: icon ? "icon:" + icon.id : ""
    height: content.tileHeight

    Button {
      anchors.fill: parent
      bordered: true
      selected: tile.chosen
      foreground: content.view.fg
      fontFamily: content.view.fontFamily
      hasCursor: content.view.hasCursorOn(tile.action)
      tooltipText: tile.icon ? tile.icon.label + (tile.icon.variant === "outline" ? " (outline)" : "") : ""
      onClicked: content.w.chooseIcon(tile.icon.id)
      onHovered: function(h) { content.view.hoverAction(tile.action, h) }
    }

    IconMark {
      anchors.centerIn: parent
      iconId: tile.icon ? tile.icon.id : Icons.defaultId
      iconData: tile.icon && tile.icon.custom ? tile.icon : null
      height: Icons.scaledHeight(tile.icon, Style.space(22))
      color: tile.chosen ? Style.selectedStateColor(content.view.fg, Color.accent) : content.view.fg
    }
  }
}
