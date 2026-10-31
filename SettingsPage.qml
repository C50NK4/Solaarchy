import QtQuick
import qs.Commons
import qs.Ui

// The gear page: what applies to every device. Each device's own choices
// live in its drawer on the devices page.
Column {
  id: page

  // Set at creation by PanelContent.qml: the bar widget and the panel.
  property var w
  property var view

  width: parent ? parent.width : 0
  spacing: Style.space(14)

  PageHeader {
    view: page.view
    title: "Settings"
    backTooltip: "Back to devices"
  }

  PanelSeparator { foreground: page.view.fg }

  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "BUILT-IN ADD-ONS"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    // Each from its addons/<id> folder; its service, when it has one, words
    // the caption.
    Repeater {
      model: page.w.builtins

      OptionRow {
        id: builtinRow
        required property var modelData
        readonly property var service: page.w.services[modelData.id] || null
        readonly property string onAction: "addon-on:" + modelData.id
        readonly property string pageAction: "addon-page:" + modelData.id
        view: page.view
        glyph: modelData.icon !== "" ? modelData.icon : "󰐱"
        label: modelData.label
        captionUrgent: !!service && service.captionUrgent === true
        caption: service && service.caption ? service.caption : modelData.description

        ToggleSwitch {
          anchors.verticalCenter: parent.verticalCenter
          checked: page.w.addonOn(builtinRow.modelData)
          foreground: page.view.fg
          hasCursor: page.view.hasCursorOn(builtinRow.onAction)
          onToggled: page.view.runAction(builtinRow.onAction)
          onHovered: function(h) { page.view.hoverAction(builtinRow.onAction, h) }
        }

        PanelActionButton {
          visible: builtinRow.modelData.page !== ""
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰅂"
          tooltipText: "More"
          foreground: page.view.fg
          fontFamily: page.view.fontFamily
          hasCursor: page.view.hasCursorOn(builtinRow.pageAction)
          onClicked: page.view.runAction(builtinRow.pageAction)
          onHovered: function(h) { page.view.hoverAction(builtinRow.pageAction, h) }
        }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(10)

    // Collapsed by default: one summary line, the switches behind the chevron.
    Item {
      width: parent.width
      implicitHeight: Math.max(notifyHeader.implicitHeight, notifyChevron.implicitHeight)

      PanelSectionHeader {
        id: notifyHeader
        anchors.verticalCenter: parent.verticalCenter
        text: "NOTIFICATIONS"
        foreground: page.view.fg
        fontFamily: page.view.fontFamily
      }

      PanelActionButton {
        id: notifyChevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: page.view.notificationsOpen ? "󰅃" : "󰅀"
        tooltipText: page.view.notificationsOpen ? "Hide the notification switches" : "Show the notification switches"
        foreground: page.view.fg
        fontFamily: page.view.fontFamily
        hasCursor: page.view.hasCursorOn("notify-more")
        onClicked: page.view.runAction("notify-more")
        onHovered: function(h) { page.view.hoverAction("notify-more", h) }
      }
    }

    Text {
      visible: !page.view.notificationsOpen
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: {
        var on = []
        // No-break spaces keep "5 %" on one line.
        if (page.w.notifyLowBattery) on.push("low battery below " + page.w.lowThreshold + "\u00a0%")
        if (page.w.notifyCritical) on.push("critical at " + page.w.criticalLevel + "\u00a0%")
        if (page.w.notifyConnection) on.push("connections")
        return on.length > 0 ? "On: " + on.join(", ") + "." : "All off."
      }
      color: page.view.dim
      font.family: page.view.fontFamily
      font.pixelSize: Style.font.caption
    }

    OptionRow {
      visible: page.view.notificationsOpen
      view: page.view
      glyph: "󰂃"
      label: "Low battery"
      caption: "Once per charge"

      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: page.w.notifyLowBattery
        foreground: page.view.fg
        hasCursor: page.view.hasCursorOn("notify-low")
        onToggled: page.w.saveSetting("notifyLowBattery", !page.w.notifyLowBattery)
        onHovered: function(h) { page.view.hoverAction("notify-low", h) }
      }
    }

    OptionRow {
      visible: page.view.notificationsOpen
      view: page.view
      glyph: "󰁺"
      label: "Warn below"
      caption: "Also turns the bar icon red"

      Stepper {
        anchors.verticalCenter: parent.verticalCenter
        view: page.view
        text: page.w.lowThreshold + " %"
        minusAction: "low-minus"
        plusAction: "low-plus"
        atMin: page.w.lowThreshold <= 5
        atMax: page.w.lowThreshold >= 50
        onMinus: page.w.stepSetting("lowThreshold", page.w.lowThreshold, -5, 5, 50)
        onPlus: page.w.stepSetting("lowThreshold", page.w.lowThreshold, 5, 5, 50)
      }
    }

    OptionRow {
      visible: page.view.notificationsOpen
      view: page.view
      glyph: "󱃍"
      label: "Critical battery"
      caption: "One more warning at " + page.w.criticalLevel + " %"

      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: page.w.notifyCritical
        foreground: page.view.fg
        hasCursor: page.view.hasCursorOn("notify-critical")
        onToggled: page.w.saveSetting("notifyCritical", !page.w.notifyCritical)
        onHovered: function(h) { page.view.hoverAction("notify-critical", h) }
      }
    }

    OptionRow {
      visible: page.view.notificationsOpen
      view: page.view
      glyph: "󰌷"
      label: "Connections"
      caption: "Gone after 5 minutes without a link, and back again. Asleep and off look the same."

      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: page.w.notifyConnection
        foreground: page.view.fg
        hasCursor: page.view.hasCursorOn("notify-connection")
        onToggled: page.w.saveSetting("notifyConnection", !page.w.notifyConnection)
        onHovered: function(h) { page.view.hoverAction("notify-connection", h) }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "BAR"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    OptionRow {
      view: page.view
      glyph: "󰈉"
      label: "Auto-hide"
      caption: "While no receiver is plugged in and no Logitech device is connected or paired over Bluetooth"

      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: page.w.hideWhenDisconnected
        foreground: page.view.fg
        hasCursor: page.view.hasCursorOn("hide-bar")
        onToggled: page.w.saveSetting("hideWhenDisconnected", !page.w.hideWhenDisconnected)
        onHovered: function(h) { page.view.hoverAction("hide-bar", h) }
      }
    }
  }

  Column {
    visible: page.w.hiddenDevices.length > 0
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "HIDDEN DEVICES"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    Repeater {
      model: page.w.hiddenDevices

      OptionRow {
        id: hiddenRow
        required property var modelData
        view: page.view
        glyph: page.w.kindIcon(modelData.kind)
        label: modelData.name

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰈈"
          tooltipText: "Show it again"
          foreground: page.view.fg
          fontFamily: page.view.fontFamily
          hasCursor: page.view.hasCursorOn("unhide:" + hiddenRow.modelData.id)
          onClicked: page.view.runAction("unhide:" + hiddenRow.modelData.id)
          onHovered: function(h) { page.view.hoverAction("unhide:" + hiddenRow.modelData.id, h) }
        }
      }
    }
  }

  // Add-ons reviewed for Solaarchy: listed before they're installed, with
  // their links; once installed, a switch like any other.
  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "CURATED ADD-ONS"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    Repeater {
      model: page.w.curatedAddons

      OptionRow {
        id: curatedRow
        required property var modelData
        readonly property var installed: page.w.installedAddon(modelData.id)
        // Greyed while there's nothing to install or open yet.
        opacity: installed || modelData.repo !== "" || modelData.page !== "" ? 1.0 : 0.5
        view: page.view
        glyph: modelData.icon
        label: modelData.label
        caption: installed ? page.addonCaption(installed, true) : modelData.note

        AddonSwitch {
          visible: !!curatedRow.installed
          addon: curatedRow.installed
        }

        PanelActionButton {
          visible: !curatedRow.installed && curatedRow.modelData.repo !== ""
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰊤"
          tooltipText: "Repository"
          foreground: page.view.fg
          fontFamily: page.view.fontFamily
          hasCursor: page.view.hasCursorOn("link:" + curatedRow.modelData.repo)
          onClicked: page.view.runAction("link:" + curatedRow.modelData.repo)
          onHovered: function(h) { page.view.hoverAction("link:" + curatedRow.modelData.repo, h) }
        }

        PanelActionButton {
          visible: !curatedRow.installed && curatedRow.modelData.page !== ""
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰖟"
          tooltipText: "Plugin page"
          foreground: page.view.fg
          fontFamily: page.view.fontFamily
          hasCursor: page.view.hasCursorOn("link:" + curatedRow.modelData.page)
          onClicked: page.view.runAction("link:" + curatedRow.modelData.page)
          onHovered: function(h) { page.view.hoverAction("link:" + curatedRow.modelData.page, h) }
        }
      }
    }
  }

  // Everything else installed with a solaarchy-addon.json; shows up by itself.
  Column {
    visible: page.w.otherAddons.length > 0
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "OTHER ADD-ONS"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    Repeater {
      model: page.w.otherAddons

      OptionRow {
        id: otherRow
        required property var modelData
        view: page.view
        glyph: modelData.icon !== "" ? modelData.icon : "󰐱"
        label: modelData.label
        caption: page.addonCaption(modelData, false)

        AddonSwitch { addon: otherRow.modelData }
      }
    }
  }

  Text {
    visible: page.w.addonErrors.length > 0
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    text: page.w.addonErrors.join("\n")
    color: page.view.urgent
    font.family: page.view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    text: "An add-on is an Omarchy plugin with a solaarchy-addon.json next to its manifest; installed ones "
      + "show up here by themselves. addons/ADDONS.md in Solaarchy's repository shows how to write one and "
      + "how to get it curated."
    color: page.view.dim
    font.family: page.view.fontFamily
    font.pixelSize: Style.font.caption
  }

  function addonCaption(addon, curated) {
    return page.w.categoryLabel(addon.category) + (curated ? "" : " · not reviewed")
      + (addon.panel ? " · opens from a device's drawer" : " · in a device's drawer")
  }

  // Turns an installed add-on's plugin on or off in Omarchy.
  component AddonSwitch: ToggleSwitch {
    property var addon
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    checked: !!addon && addon.enabled
    foreground: page.view.fg
    hasCursor: !!addon && page.view.hasCursorOn("addon-toggle:" + addon.id)
    onToggled: page.view.runAction("addon-toggle:" + addon.id)
    onHovered: function(h) { page.view.hoverAction("addon-toggle:" + addon.id, h) }
  }
}
