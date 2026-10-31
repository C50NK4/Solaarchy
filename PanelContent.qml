import QtQuick
import qs.Commons
import qs.Ui
import "icons.js" as Icons

// Solaarchy panel body. Pages that swap in place: the devices (each with a
// drawer for its own settings), the bar icon picker opened from the big icon,
// Settings behind the gear, and a built-in add-on's own page.
Item {
  id: content

  // Set once, at creation, by Panel.qml: the bar widget holding the device
  // state, and the panel for colours, page and keyboard-cursor state.
  property var w
  property var view

  implicitHeight: content.view.page === "icons" ? iconsPage.implicitHeight
    : content.view.page === "settings" ? settingsPage.implicitHeight
    : content.view.page.indexOf("addon:") === 0 ? addonPage.implicitHeight
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
      // The icon itself opens the bar icon picker.
      iconComponent: Component {
        Item {
          implicitWidth: heroMark.implicitWidth
          implicitHeight: heroMark.height

          BorderSurface {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            radius: Style.cornerRadius
            color: heroMouse.containsMouse || content.view.hasCursorOn("icons")
              ? Style.hoverFillFor(content.view.fg, content.view.fg) : "transparent"
            borderSpec: Border.none()
            Behavior on color { ColorAnimation { duration: 60 } }
          }

          IconMark {
            id: heroMark
            iconId: content.w.currentIcon.id
            iconData: content.w.currentIcon.custom ? content.w.currentIcon : null
            height: Icons.fitHeight(content.w.currentIcon, Style.font.display)
            color: content.w.anyLow ? content.view.urgent : content.view.fg
            Behavior on color { ColorAnimation { duration: 200 } }
          }

          MouseArea {
            id: heroMouse
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: content.view.hoverAction("icons", containsMouse)
            onClicked: content.view.runAction("icons")
          }

          PanelToolTip {
            visible: heroMouse.containsMouse
            text: "Bar icon: click to change"
            fontFamily: content.view.fontFamily
          }
        }
      }
      trailingControl: Component {
        Row {
          spacing: Style.space(4)

          PanelActionButton {
            iconText: "󰒓"
            tooltipText: "Settings"
            foreground: content.view.fg
            fontFamily: content.view.fontFamily
            hasCursor: content.view.hasCursorOn("settings")
            onClicked: content.view.runAction("settings")
            onHovered: function(h) { content.view.hoverAction("settings", h) }
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
        visible: content.w.shown.length === 0
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: content.w.lastError !== "" ? content.w.lastError
          : (!content.w.loaded ? "Reading devices…"
            : content.w.hiddenDevices.length > 0 ? "Every device is hidden. Settings brings them back."
            : content.w.receivers.length > 0 ? "No devices paired with " + content.w.receivers.join(", ")
            : "No Logitech receiver or device connected")
        color: content.w.lastError !== "" ? content.view.urgent : content.view.dim
        font.family: content.view.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        model: content.w.shown

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
          readonly property bool lightOn: content.w.backlightOn(modelData)
          readonly property real labelsGap: Style.space(8)
          readonly property string drawerAction: "drawer:" + modelData.id
          readonly property bool drawerOpen: content.view.drawerId === String(modelData.id)
          width: parent.width
          spacing: Style.space(7)

          Item {
            width: parent.width
            implicitHeight: Math.max(kindGlyph.implicitHeight, labels.implicitHeight, percent.implicitHeight, chevron.implicitHeight)
            // An asleep device dims; its drawer below does not, since all of
            // it works while the device sleeps.
            opacity: deviceItem.live ? 1.0 : 0.6

            // The whole row opens the drawer; the bulb and chevron sit on top.
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: content.view.runAction(deviceItem.drawerAction)
            }

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

              // Name, with the backlight switch in the space after it on keyboards.
              Item {
                width: parent.width
                implicitHeight: Math.max(nameText.implicitHeight, bulb.visible ? bulb.implicitHeight : 0)

                Text {
                  id: nameText
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, parent.width - (bulb.visible ? bulb.width + Style.space(8) : 0))
                  textFormat: Text.PlainText
                  text: deviceItem.modelData.name
                  color: content.view.fg
                  font.family: content.view.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                PanelActionButton {
                  id: bulb
                  // Centred in the free space between the end of the name and
                  // the percentage, which starts labelsGap past this row.
                  readonly property real freeStart: nameText.width
                  readonly property real freeEnd: parent.width + deviceItem.labelsGap
                  visible: deviceItem.hasBacklight
                  x: Math.round(freeStart + Math.max(Style.space(4), (freeEnd - freeStart - width) / 2))
                  anchors.verticalCenter: parent.verticalCenter
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
                      + (content.w.addonTooltip(deviceItem.modelData) !== ""
                         ? "\n" + content.w.addonTooltip(deviceItem.modelData) : "")
                  onClicked: content.w.toggleBacklight(deviceItem.modelData)
                  onHovered: function(h) { content.view.hoverAction("backlight:" + deviceItem.modelData.id, h) }
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
              anchors.right: chevron.left
              anchors.rightMargin: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              text: (deviceItem.modelData.battery && deviceItem.modelData.battery.charging ? "󱐋 " : "")
                + content.w.percentText(deviceItem.modelData)
              color: deviceItem.low ? content.view.urgent : content.view.fg
              font.family: content.view.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            PanelActionButton {
              id: chevron
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              fontSize: Style.font.body
              iconText: deviceItem.drawerOpen ? "󰅃" : "󰅀"
              tooltipText: deviceItem.drawerOpen ? "Less" : "More for this device"
              foreground: content.view.dim
              hoverColor: content.view.fg
              fontFamily: content.view.fontFamily
              hasCursor: content.view.hasCursorOn(deviceItem.drawerAction)
              onClicked: content.view.runAction(deviceItem.drawerAction)
              onHovered: function(h) { content.view.hoverAction(deviceItem.drawerAction, h) }
            }
          }

          // Charge bar
          Item {
            width: parent.width
            implicitHeight: Style.space(6)
            visible: !!deviceItem.modelData.battery
            opacity: deviceItem.live ? 1.0 : 0.6

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

          DeviceDrawer {
            visible: deviceItem.drawerOpen
            device: deviceItem.modelData
          }
        }
      }

      MessageText {
        visible: content.w.actionError !== ""
        text: content.w.actionError
        urgent: true
      }

      // A built-in add-on's word on what it can't do right now.
      Repeater {
        model: content.w.builtins

        MessageText {
          required property var modelData
          readonly property var service: content.w.services[modelData.id] || null
          visible: text !== ""
          text: service && service.message ? service.message : ""
          urgent: true
        }
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

  // ================= Bar icon picker =================
  // Every section is a header over a full-width block of equal tiles, so all
  // tiles share one width, gap and height and line up across sections.
  Column {
    id: iconsPage
    visible: content.view.page === "icons"
    width: parent.width
    spacing: Style.space(14)

    PageHeader {
      view: content.view
      title: "Bar icon"
      backTooltip: "Back to devices"
    }

    PanelSeparator { foreground: content.view.fg }

    IconSection {
      title: "SOLAAR"
      icons: [Icons.byId("solaar")]
      columns: 1
    }

    // Filled icons on the first row, their outline versions below, each row
    // led by its auto pick.
    IconSection {
      title: "DEVICES"
      icons: Icons.deviceRow("filled").concat(Icons.deviceRow("outline"))
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

  // ================= Settings and add-on pages =================
  SettingsPage {
    id: settingsPage
    visible: content.view.page === "settings"
    w: content.w
    view: content.view
  }

  // A built-in add-on's page, built fresh each time it is shown.
  Loader {
    id: addonPage
    readonly property string addonId: content.view.page.indexOf("addon:") === 0 ? content.view.page.slice(6) : ""
    visible: addonId !== ""
    width: parent.width

    onAddonIdChanged: {
      var addon = content.w.builtinById(addonId)
      if (addon && addon.page !== "")
        setSource(Util.fileUrl(addon.page), { "service": content.w.services[addon.id] || null,
                                              "w": content.w, "view": content.view })
      else
        source = ""
    }
  }

  // What can be set for one device alone, under its row: a section per
  // capability something fills (built-in add-ons, installed ones, curated
  // ones to come), the other capabilities on one line, and Hide. Every
  // Solaarchy control goes through Panel.qml's runAction, the same path the
  // keyboard cursor takes.
  component DeviceDrawer: Rectangle {
    id: drawer
    property var device: null
    readonly property string deviceId: device ? String(device.id) : ""
    readonly property var layout: device ? content.w.drawerSections(device) : ({ "sections": [], "also": [] })
    width: parent ? parent.width : 0
    implicitHeight: drawerColumn.implicitHeight + Style.space(20)
    radius: Style.cornerRadius
    color: Qt.rgba(content.view.fg.r, content.view.fg.g, content.view.fg.b, 0.05)

    Column {
      id: drawerColumn
      x: Style.space(10)
      y: Style.space(10)
      width: parent.width - Style.space(20)
      spacing: Style.space(12)

      Repeater {
        model: drawer.layout.sections

        Column {
          id: section
          required property var modelData
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: section.modelData.label.toUpperCase()
            foreground: content.view.fg
            fontFamily: content.view.fontFamily
          }

          Repeater {
            model: section.modelData.addons

            AddonSlot {
              required property var modelData
              addon: modelData
              device: drawer.device
            }
          }

          Repeater {
            model: section.modelData.off

            MessageText {
              required property var modelData
              text: modelData.label + (modelData.builtin ? " is built in, switched off in Settings."
                : " is installed but turned off in Omarchy's plugins.")
            }
          }

          Repeater {
            model: section.modelData.known

            LabelButton {
              required property var modelData
              available: false
              glyph: modelData.icon
              text: modelData.label + " add-on · " + (modelData.repo !== "" || modelData.page !== ""
                ? "not installed" : "in development")
              tooltip: modelData.note
            }
          }
        }
      }

      MessageText {
        visible: drawer.layout.also.length > 0
        text: "Also: " + drawer.layout.also.join(" · ") + ". No add-on for these yet."
      }

      MessageText {
        visible: !!drawer.device && content.w.featuresOf(drawer.device) === null
        text: "What it can do shows here once it has been read awake."
      }

      LabelButton {
        glyph: "󰈉"
        text: "Hide this device"
        tooltip: "Settings brings it back"
        action: "hide:" + drawer.deviceId
      }
    }
  }

  // One add-on in a device's drawer: its own drawer QML (mouse only: the
  // keyboard cursor stays on Solaarchy's controls), and a button for its
  // floating panel when it has one.
  component AddonSlot: Column {
    id: slot
    property var addon
    property var device
    width: parent ? parent.width : 0
    spacing: Style.space(6)

    AddonHost {
      id: host
      addon: slot.addon
      device: slot.device
    }

    Loader {
      id: addonLoader
      width: parent.width
      Component.onCompleted: {
        // A fresh device each time: the whole row is rebuilt when it changes.
        if (slot.addon.drawer !== "")
          setSource(Util.fileUrl(slot.addon.drawer), { "device": content.w.addonDevice(slot.device), "host": host })
      }
    }

    MessageText {
      visible: addonLoader.status === Loader.Error
      text: slot.addon.label + " could not load its drawer."
      urgent: true
    }

    LabelButton {
      visible: slot.addon.panel
      glyph: slot.addon.icon !== "" ? slot.addon.icon : "󰏌"
      text: "Open " + slot.addon.label
      action: "addon:" + slot.addon.id + ":" + String(slot.device.id)
    }
  }

  // What an add-on's drawer QML gets as `host` (api 1, see addons/ADDONS.md).
  component AddonHost: QtObject {
    property var addon
    property var device
    readonly property int api: 1
    // Built-in add-ons only: their service, and the panel for the keyboard
    // cursor.
    readonly property var service: addon && addon.builtin ? content.w.services[addon.id] || null : null
    readonly property var view: addon && addon.builtin ? content.view : null
    readonly property color foreground: content.view.fg
    readonly property color dim: content.view.dim
    readonly property color urgent: content.view.urgent
    readonly property string fontFamily: content.view.fontFamily
    readonly property string lockPath: content.w.lockPath

    // Opens the add-on's own panel; extra keys join {"device": {...}}.
    function openPanel(extra) { content.w.openAddonPanel(addon, device, extra) }
    // A fresh device read, after the add-on changed something.
    function refresh() { content.w.refresh() }
  }

  // A small button with words, in the Solaar button's look. Not available:
  // dimmed, but still shows its tooltip.
  component LabelButton: BorderSurface {
    id: labelButton
    property string glyph: ""
    property string text: ""
    property string tooltip: ""
    property string action: ""
    property bool available: true
    readonly property bool hasCursor: available && content.view.hasCursorOn(action)
    readonly property bool hot: available && (labelMouse.containsMouse || hasCursor)
    implicitWidth: labelRow.implicitWidth + Style.space(12)
    implicitHeight: Math.max(Style.space(22), labelRow.implicitHeight + Style.space(4))
    radius: Style.cornerRadius
    color: hot ? Style.hoverFillFor(content.view.fg, content.view.fg) : "transparent"
    borderSpec: Border.none()
    opacity: available ? 1.0 : 0.5

    Behavior on color { ColorAnimation { duration: 60 } }

    Row {
      id: labelRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: labelButton.glyph
        color: content.view.dim
        font.family: content.view.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: labelButton.text
        color: content.view.dim
        font.family: content.view.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      id: labelMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: labelButton.available ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (labelButton.available) content.view.hoverAction(labelButton.action, containsMouse)
      onClicked: if (labelButton.available) content.view.runAction(labelButton.action)
    }

    PanelToolTip {
      visible: labelMouse.containsMouse && labelButton.tooltip !== ""
      text: labelButton.tooltip
      fontFamily: content.view.fontFamily
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
  readonly property int tileColumns: 4
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
      // leftover pixels all go to one column, so every row ends exactly at
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
  // keyboard stays shorter than a mouse, exactly as in the bar. An auto tile
  // draws the device icon it stands for right now, marked with a small A.
  component IconTile: Item {
    id: tile
    property var icon: null
    readonly property bool isAuto: !!icon && Icons.isAuto(icon.id)
    readonly property var drawn: isAuto ? content.w.resolveIcon(icon.id) : icon
    readonly property bool chosen: !!icon && content.w.chosenIcon === icon.id
    readonly property string action: icon ? "icon:" + icon.id : ""
    height: content.tileHeight

    Button {
      anchors.fill: parent
      bordered: true
      selected: tile.chosen
      foreground: content.view.fg
      fontFamily: content.view.fontFamily
      hasCursor: content.view.hasCursorOn(tile.action)
      tooltipText: tile.icon ? tile.icon.label + (tile.icon.variant === "outline" ? " (outline)" : "")
        + (tile.isAuto ? ": follows your devices (now " + tile.drawn.label + ")" : "") : ""
      onClicked: content.w.chooseIcon(tile.icon.id)
      onHovered: function(h) { content.view.hoverAction(tile.action, h) }
    }

    IconMark {
      anchors.centerIn: parent
      iconId: tile.drawn ? tile.drawn.id : Icons.defaultId
      iconData: tile.drawn && tile.drawn.custom ? tile.drawn : null
      height: Icons.scaledHeight(tile.drawn, Style.space(22))
      color: tile.chosen ? Style.selectedStateColor(content.view.fg, Color.accent) : content.view.fg
    }

    Text {
      visible: tile.isAuto
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.margins: Style.space(4)
      textFormat: Text.PlainText
      text: "A"
      color: content.view.dim
      font.family: content.view.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
